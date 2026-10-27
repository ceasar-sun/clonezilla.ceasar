#!/bin/bash

# Colors for diff and output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 -i \${input}.iso -o \${output}.qcow2 [--output-iso] -kb key1=val1 [key2=val2 ...]"
    exit 1
}

# Parse arguments
INPUT_ISO=""
OUTPUT_QCOW2=""
OUTPUT_ISO_FLAG=false
KB_PARAMS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i) INPUT_ISO="$2"; shift 2 ;;
        -o) OUTPUT_QCOW2="$2"; shift 2 ;;
        --output-iso) OUTPUT_ISO_FLAG=true; shift ;;
        -kb) 
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do 
                KB_PARAMS+=("$1")
                shift
            done 
            ;;
        *) usage ;;
    esac
done

if [[ -z "$INPUT_ISO" || -z "$OUTPUT_QCOW2" || ${#KB_PARAMS[@]} -eq 0 ]]; then
    usage
fi

if [[ ! -f "$INPUT_ISO" ]]; then
    echo -e "${RED}Error: Input ISO '$INPUT_ISO' not found.${NC}"
    exit 1
fi

# Convert paths to absolute paths
ORIG_INPUT_DIR=$(dirname "$INPUT_ISO")
ORIG_INPUT_BASE=$(basename "$INPUT_ISO" .iso)

INPUT_ISO=$(realpath "$INPUT_ISO")
OUTPUT_DIR=$(dirname "$OUTPUT_QCOW2")
OUTPUT_DIR_ABS=$(realpath "$OUTPUT_DIR")
OUTPUT_BASE=$(basename "$OUTPUT_QCOW2")
OUTPUT_QCOW2="$OUTPUT_DIR_ABS/$OUTPUT_BASE"

# Create a temporary directory for processing
WORKDIR=$(mktemp -d)
# Ensure cleanup on exit
trap 'rm -rf "$WORKDIR"' EXIT

EXTRACT_DIR="$WORKDIR/extracted"
mkdir -p "$EXTRACT_DIR"

echo -e "${BLUE}Extracting ISO...${NC}"
xorriso -osirrox on -indev "$INPUT_ISO" -extract / "$EXTRACT_DIR" > /dev/null 2>&1

# Ensure extracted files are writable
chmod -R u+w "$EXTRACT_DIR"

# Write parameters to a temporary file for awk
printf "%s\n" "${KB_PARAMS[@]}" > "$WORKDIR/kb_params.txt"

# Targeted configuration files in the extracted directory
FILES=("$EXTRACT_DIR/EFI/BOOT/grub.cfg" "$EXTRACT_DIR/boot/grub2/grub.cfg")
MODIFIED_ANY=false

for cfg in "${FILES[@]}"; do
    if [[ ! -f "$cfg" ]]; then
        continue
    fi
    
    echo -e "${BLUE}Processing $cfg...${NC}"
    cp "$cfg" "$cfg-bak"
    
    awk -v param_file="$WORKDIR/kb_params.txt" '
    BEGIN {
        while ((getline < param_file) > 0) {
            params[++n] = $0
        }
    }
    function modify(line) {
        # Remove standalone quiet
        gsub(/[[:space:]]+quiet[[:space:]]+/, " ", line)
        gsub(/[[:space:]]+quiet$/, "", line)
        gsub(/^quiet[[:space:]]+/, "", line)
        gsub(/^quiet$/, "", line)

        for (i=1; i<=n; i++) {
            split(params[i], kv, "=")
            key = kv[1]
            val = substr(params[i], length(key) + 2)
            
            pattern = "[[:space:]]" key "="
            if (line ~ pattern) {
                start = index(line, " " key "=")
                if (start == 0) {
                    start = index(line, "\t" key "=")
                }
                if (start > 0) {
                    before = substr(line, 1, start)
                    after = substr(line, start + length(key) + 2)
                    
                    if (after ~ /^"/) {
                        match_pos = index(substr(after, 2), "\"")
                        if (match_pos > 0) {
                            after_val = substr(after, match_pos + 2)
                        } else {
                            after_val = ""
                        }
                    } else {
                        space_pos = index(after, " ")
                        if (space_pos == 0) {
                            space_pos = index(after, "\t")
                        }
                        if (space_pos > 0) {
                            after_val = substr(after, space_pos)
                        } else {
                            after_val = ""
                        }
                    }
                    line = before key "=" val after_val
                }
            } else {
                line = line " " key "=" val
            }
        }
        return line
    }
    $1 ~ /^(linux|linux16|linuxefi)$/ {
        $0 = modify($0)
    }
    { print }
    ' "$cfg-bak" > "$cfg"

    # Show diff between original and modified configs
    echo -e "${BLUE}Diff for $cfg:${NC}"
    diff --color=always -u "$cfg-bak" "$cfg"
    MODIFIED_ANY=true
done

if ! $MODIFIED_ANY; then
    echo -e "${RED}Warning: No boot config files (grub.cfg) found/modified!${NC}"
fi

# Rebuild ISO
echo -e "${BLUE}Rebuilding ISO...${NC}"
TMP_ISO="$WORKDIR/modified.iso"

# Retrieve original boot options using xorriso to maintain identical boot geometry
BOOT_OPTS=$(xorriso -indev "$INPUT_ISO" -report_el_torito as_mkisofs 2>/dev/null | grep -E '^--?[a-zA-Z0-9_-]+' | tr '\n' ' ')

if [[ -z "$BOOT_OPTS" ]]; then
    echo -e "${RED}Error: Failed to extract boot layout from $INPUT_ISO${NC}"
    exit 1
fi

# Check and modify embedded EFI boot image if present in the boot configuration
PART_LINE=$(echo "$BOOT_OPTS" | grep -oE '\-append_partition 2 [^ ]+ \-\-interval:local_fs:[0-9]+d-[0-9]+d::[^ ]+')
if [[ -n "$PART_LINE" ]]; then
    echo -e "${BLUE}Modifying embedded EFI partition grub.cfg...${NC}"
    START_BLOCK=$(echo "$PART_LINE" | sed -E 's/.*local_fs:([0-9]+)d-.*/\1/')
    END_BLOCK=$(echo "$PART_LINE" | sed -E 's/.*-([0-9]+)d::.*/\1/')
    COUNT=$((END_BLOCK - START_BLOCK + 1))
    
    # Extract EFI FAT image
    dd if="$INPUT_ISO" of="$WORKDIR/efi.img" bs=512 skip=$START_BLOCK count=$COUNT status=none
    
    # Read the grub.cfg from FAT image
    mtype -i "$WORKDIR/efi.img" ::/EFI/BOOT/grub.cfg > "$WORKDIR/efi_grub.cfg-bak" 2>/dev/null
    
    if [[ -f "$WORKDIR/efi_grub.cfg-bak" ]]; then
        # Apply parameter modifications
        awk -v param_file="$WORKDIR/kb_params.txt" '
        BEGIN {
            while ((getline < param_file) > 0) {
                params[++n] = $0
            }
        }
        function modify(line) {
            gsub(/[[:space:]]+quiet[[:space:]]+/, " ", line)
            gsub(/[[:space:]]+quiet$/, "", line)
            gsub(/^quiet[[:space:]]+/, "", line)
            gsub(/^quiet$/, "", line)

            for (i=1; i<=n; i++) {
                split(params[i], kv, "=")
                key = kv[1]
                val = substr(params[i], length(key) + 2)
                
                pattern = "[[:space:]]" key "="
                if (line ~ pattern) {
                    start = index(line, " " key "=")
                    if (start == 0) {
                        start = index(line, "\t" key "=")
                    }
                    if (start > 0) {
                        before = substr(line, 1, start)
                        after = substr(line, start + length(key) + 2)
                        
                        if (after ~ /^"/) {
                            match_pos = index(substr(after, 2), "\"")
                            if (match_pos > 0) {
                                after_val = substr(after, match_pos + 2)
                            } else {
                                after_val = ""
                            }
                        } else {
                            space_pos = index(after, " ")
                            if (space_pos == 0) {
                                space_pos = index(after, "\t")
                            }
                            if (space_pos > 0) {
                                after_val = substr(after, space_pos)
                            } else {
                                after_val = ""
                            }
                        }
                        line = before key "=" val after_val
                    }
                } else {
                    line = line " " key "=" val
                }
            }
            return line
        }
        $1 ~ /^(linux|linux16|linuxefi)$/ {
            $0 = modify($0)
        }
        { print }
        ' "$WORKDIR/efi_grub.cfg-bak" > "$WORKDIR/efi_grub.cfg"
        
        # Copy back to the FAT image
        mcopy -o -i "$WORKDIR/efi.img" "$WORKDIR/efi_grub.cfg" ::/EFI/BOOT/grub.cfg
        mcopy -o -i "$WORKDIR/efi.img" "$WORKDIR/efi_grub.cfg-bak" ::/EFI/BOOT/grub.cfg-bak
        
        # Print diff for the EFI partition's grub.cfg
        echo -e "${BLUE}Diff for EFI partition /EFI/BOOT/grub.cfg:${NC}"
        diff --color=always -u "$WORKDIR/efi_grub.cfg-bak" "$WORKDIR/efi_grub.cfg"
    fi
    
    # Replace parameters in BOOT_OPTS to use our modified efi.img
    UUID=$(echo "$PART_LINE" | awk '{print $3}')
    NEW_PART_LINE="-append_partition 2 $UUID \"$WORKDIR/efi.img\""
    BOOT_OPTS=${BOOT_OPTS//"$PART_LINE"/"$NEW_PART_LINE"}
    BOOT_OPTS=$(echo "$BOOT_OPTS" | sed -E "s/--interval:appended_partition_2_start_[0-9]+s_size_/--interval:appended_partition_2_start_0s_size_/g")
fi

# Execute mkisofs to rebuild ISO with modified files
eval "xorriso -as mkisofs $BOOT_OPTS -o \"$TMP_ISO\" \"$EXTRACT_DIR\" >/dev/null 2>&1"

# Convert to qcow2
echo -e "${BLUE}Converting to qcow2...${NC}"
qemu-img convert -f raw -O qcow2 "$TMP_ISO" "$OUTPUT_QCOW2"

# Handle --output-iso
if $OUTPUT_ISO_FLAG; then
    NEW_ISO_NAME="$ORIG_INPUT_DIR/${ORIG_INPUT_BASE}-new.iso"
    cp "$TMP_ISO" "$NEW_ISO_NAME"
    echo -e "${GREEN}Modified ISO saved as: $NEW_ISO_NAME${NC}"
fi

echo -e "${GREEN}Done! Output saved to: $OUTPUT_QCOW2${NC}"
