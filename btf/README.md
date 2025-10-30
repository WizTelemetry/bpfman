# BTF artifacts and generation

This folder contains detached BTF files (`*.vmlinux`) used by bpfman when the running host doesn't expose a suitable system BTF.

## Naming convention

- `<kernel-build-string>.vmlinux`, for example:
  - `4.19.90-2107.6.0.0100.oe1.bclinux.x86_64.vmlinux`
- The file name comes from the debuginfo RPM name:
  - `kernel-debuginfo-<kernel-build-string>.rpm` -> `<kernel-build-string>.vmlinux`

## How to generate from a debuginfo RPM

Use the helper script in this directory:

- Requirements: `pahole`, `rpm2cpio`, `cpio` (and `gzip`/`xz` if the vmlinux is compressed). Optional: `bpftool` to validate.
- Example:

```
./generate_btf_from_rpm.sh -o ./ kernel-debuginfo-4.19.90-2107.6.0.0100.oe1.bclinux.x86_64.rpm
```

This produces `./4.19.90-2107.6.0.0100.oe1.bclinux.x86_64.vmlinux`.

### What the script does (path logic)

- The RPM payload is extracted into a temporary directory (e.g. `/tmp/btfgen.XXXXXX`).
- Inside that temp directory, the script searches for `vmlinux` candidates and prefers:
  1. `${TMPDIR}/usr/lib/debug/lib/modules/<version>/vmlinux` (uncompressed, most standard)
  2. `${TMPDIR}/usr/lib/debug/boot/vmlinux-<version>`
  3. Else: the largest `vmlinux*` candidate found (heuristic fallback)
- If the chosen file is compressed (`.xz`/`.gz`), it is decompressed in place under the temp directory.
- Then `pahole --btf_encode_detached <out>.vmlinux <selected vmlinux>` is invoked to produce the detached BTF.
- The temp directory is removed automatically on exit.

Important: the script never uses the host's `/usr/lib/debug` or `/sys/kernel/btf`; it only operates on files extracted from the provided RPM. The resulting BTF therefore corresponds strictly to that RPM's kernel build.

### Validate the output (optional)

```
bpftool btf dump file ./4.19.90-2107.6.0.0100.oe1.bclinux.x86_64.vmlinux | head -n 5
```

### Troubleshooting

- "no vmlinux file found": ensure you're using a proper kernel debuginfo RPM (not just headers/devel).
- Missing tools: install `rpm2cpio` and `cpio`; for `.xz` inputs, install `xz-utils`.
- If a file already exists and you want to overwrite, pass `-f` to the script.

## How bpfman chooses a BTF at runtime

- If the host exposes `/sys/kernel/btf/vmlinux`, that system BTF is preferred at runtime.
- Otherwise, user-provided `*.vmlinux` files here are used when their names match the running kernel (exact or prefix match).
