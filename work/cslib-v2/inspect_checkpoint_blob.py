#!/usr/bin/env python3
"""Read-only inspection of a packed Lean checkpoint in an OCaml 4.14 .vo.

This is deliberately not an unmarshaler. It validates the ObjFile directory,
library segment digest, expected Libobject/envelope encoding, inner Marshal
header/root shape, and blob digest. It does not typecheck the inner graph or
parse the enclosing Marshal graph. Candidate discovery is a bounded byte scan.
All filesystem opens are read-only; each I/O buffer is at most 64 KiB.
"""

import argparse
import hashlib
import json
import os
import struct


BUFFER_SIZE = 64 * 1024
MASK32 = (1 << 32) - 1


def exact(stream, size):
    if not 0 <= size <= BUFFER_SIZE:
        raise ValueError("oversized metadata read")
    data = stream.read(size)
    if len(data) != size:
        raise ValueError("truncated metadata")
    return data


def uint(stream, size):
    return int.from_bytes(exact(stream, size), "big")


def ocaml_string_hash(data):
    """Hashtbl.hash on a string, from OCaml 4.14 runtime/hash.c, seed 0."""
    def rotate(value, count):
        return ((value << count) | (value >> (32 - count))) & MASK32

    value = 0
    for offset in range(0, len(data), 4):
        word = int.from_bytes(data[offset:offset + 4], "little")
        word = rotate(word * 0xCC9E2D51 & MASK32, 15)
        word = word * 0x1B873593 & MASK32
        value = rotate(value ^ word, 13)
        value = (value * 5 + 0xE6546B64) & MASK32
    value ^= len(data)
    value ^= value >> 16
    value = value * 0x85EBCA6B & MASK32
    value ^= value >> 13
    value = value * 0xC2B2AE35 & MASK32
    value ^= value >> 16
    return value & 0x3FFFFFFF


def marshal_header(stream):
    magic = uint(stream, 4)
    if magic == 0x8495A6BE:
        data_bytes, objects, words32, words64 = struct.unpack(">4I", exact(stream, 16))
        return {"header_bytes": 20, "data_bytes": data_bytes,
                "objects": objects, "words32": words32, "words64": words64}
    if magic == 0x8495A6BF:
        if uint(stream, 4) != 0:
            raise ValueError("unsupported big Marshal header")
        data_bytes, objects, words64 = struct.unpack(">3Q", exact(stream, 24))
        return {"header_bytes": 32, "data_bytes": data_bytes,
                "objects": objects, "words64": words64}
    raise ValueError("not an OCaml Marshal header")


def library_segment(stream):
    size = os.fstat(stream.fileno()).st_size
    if uint(stream, 4) != 0x436F7121:
        raise ValueError("not a Rocq ObjFile")
    version, summary_pos = uint(stream, 4), uint(stream, 8)
    if not 16 <= summary_pos <= size - 4:
        raise ValueError("invalid ObjFile summary offset")
    stream.seek(summary_pos)
    count = uint(stream, 4)
    if not 1 <= count <= 64:
        raise ValueError("unsupported segment count")
    library = None
    for _ in range(count):
        name_len = uint(stream, 4)
        if not 1 <= name_len <= 1024:
            raise ValueError("unsupported segment name length")
        name = exact(stream, name_len)
        position, length = uint(stream, 8), uint(stream, 8)
        digest = exact(stream, 16)
        if not 16 <= position <= position + length + 16 <= summary_pos:
            raise ValueError("segment lies outside ObjFile data")
        if name == b"library":
            if library is not None:
                raise ValueError("duplicate library segment")
            library = {"offset": position, "bytes": length,
                       "md5": digest.hex()}
    if stream.tell() != size or library is None:
        raise ValueError("invalid summary end or missing library segment")
    stream.seek(library["offset"] + library["bytes"])
    if exact(stream, 16).hex() != library["md5"]:
        raise ValueError("library trailer digest disagrees with directory")
    stream.seek(library["offset"])
    header = marshal_header(stream)
    if header["header_bytes"] + header["data_bytes"] != library["bytes"]:
        raise ValueError("library Marshal size disagrees with directory")
    return version, library


def scan_and_digest(stream, offset, size, needle=None):
    """One fixed buffer; retain only bounded candidate offsets across reads."""
    stream.seek(offset)
    buffer = bytearray(BUFFER_SIZE)
    view = memoryview(buffer)
    digest = hashlib.md5()
    candidates = []
    consumed = tail = 0
    while consumed < size:
        amount = min(size - consumed, BUFFER_SIZE - tail)
        got = stream.readinto(view[tail:tail + amount])
        if not got:
            raise ValueError("truncated segment or blob")
        digest.update(view[tail:tail + got])
        end = tail + got
        if needle is not None:
            start = 0
            while True:
                found = buffer.find(needle, start, end)
                if found < 0:
                    break
                candidates.append(offset + consumed - tail + found)
                if len(candidates) > 16:
                    raise ValueError("too many envelope candidates")
                start = found + 1
        consumed += got
        tail = min(len(needle) - 1, end) if needle is not None else 0
        if tail:
            view[:tail] = view[end - tail:end]
    return digest.hexdigest(), candidates


def read_candidate(stream, candidate, needle, segment_end):
    stream.seek(candidate)
    if exact(stream, len(needle)) != needle:
        raise ValueError("candidate prefix changed")
    # AtomicObject (Dyn (expected_tag, { state_format; state_digest; state_blob })).
    if exact(stream, 1) != b"\xb0":
        raise ValueError("expected packed record with three fields")
    encoded_format = uint(stream, 1)
    if encoded_format not in (0x41, 0x42, 0x43):
        raise ValueError("unsupported packed state format")
    if exact(stream, 2) != b"\x09\x20":
        raise ValueError("expected 32-byte digest string")
    expected_digest = exact(stream, 32).decode("ascii")
    if any(char not in "0123456789abcdef" for char in expected_digest):
        raise ValueError("invalid hexadecimal digest")
    code = uint(stream, 1)
    if code not in (0x0A, 0x15):
        raise ValueError("expected a fresh large blob string")
    blob_bytes = uint(stream, 4 if code == 0x0A else 8)
    blob_offset = stream.tell()
    if blob_bytes < 25 or blob_offset + blob_bytes > segment_end:
        raise ValueError("blob exceeds library segment")
    header = marshal_header(stream)
    if header["header_bytes"] + header["data_bytes"] != blob_bytes:
        raise ValueError("inner Marshal size disagrees with blob string")
    # All supported packed formats have a 14-field top-level tuple.
    if exact(stream, 1) != b"\x08" or uint(stream, 4) != 14 << 10:
        raise ValueError("expected state root: tag 0, fourteen fields")
    digest, _ = scan_and_digest(stream, blob_offset, blob_bytes)
    if digest != expected_digest:
        raise ValueError("blob MD5 does not match its envelope")
    return {"envelope_offset": candidate, "state_format": encoded_format - 0x40,
            "blob_offset": blob_offset, "blob_bytes": blob_bytes,
            "blob_md5": digest, "marshal": header}


def sharing_table(objects):
    """Capacity implied by extern_record_location/extern_resize_position_table."""
    capacity = 256
    last_peak = capacity * 129 // 8
    last_threshold = None
    while objects >= capacity * 2 // 3:
        previous = capacity
        last_threshold = previous * 2 // 3
        capacity *= 8 if capacity < 1024 * 1024 else 2
        # 16-byte object_position plus one occupancy bit per slot (64-bit OCaml).
        last_peak = (previous + capacity) * 129 // 8
    return {"final_slots": capacity, "final_bytes": capacity * 129 // 8,
            "last_resize_object_threshold": last_threshold,
            "last_resize_old_plus_new_bytes": last_peak,
            "next_resize_object_threshold": capacity * 2 // 3}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint")
    args = parser.parse_args()
    tag = ocaml_string_hash(b"LEAN-IMPORT-STATE-V2")
    # AtomicObject: tag 6, one field. Dyn: tag 0, two fields. Int32 tag follows.
    needle = b"\x96\xa0\x02" + tag.to_bytes(4, "big")
    with open(args.checkpoint, "rb", buffering=0) as stream:
        version, segment = library_segment(stream)
        digest, candidates = scan_and_digest(
            stream, segment["offset"], segment["bytes"], needle)
        if digest != segment["md5"]:
            raise ValueError("library segment digest failed")
        valid, rejected = [], 0
        for candidate in candidates:
            try:
                envelope = read_candidate(
                    stream, candidate, needle, segment["offset"] + segment["bytes"])
            except (ValueError, UnicodeError):
                rejected += 1
                continue
            envelope["sharing_table_64bit"] = sharing_table(envelope["marshal"]["objects"])
            valid.append(envelope)
    if len(valid) != 1:
        raise ValueError(f"expected one validated envelope, found {len(valid)}")
    print(json.dumps({"checkpoint": args.checkpoint, "vo_version": version,
                      "library_segment": segment, "dynamic_tag_hash": tag,
                      "rejected_candidates": rejected, "checkpoint_state": valid[0],
                      "validation": "segment and blob MD5, Dyn/record envelope, "
                      "Marshal size and root shape; not inner-graph typechecking "
                      "or enclosing Marshal grammar validation"}, indent=2))


if __name__ == "__main__":
    main()
