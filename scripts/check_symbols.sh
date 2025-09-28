#!/bin/bash
# Symbol verification script for static library completeness
# Usage: ./check_symbols.sh <path_to_static_lib>

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check symbols in a static library
check_sym() {
    local lib_path="$1"
    local lib_name=$(basename "$lib_path")
    
    echo -e "${YELLOW}Checking symbols in: $lib_name${NC}"
    
    if [[ ! -f "$lib_path" ]]; then
        echo -e "${RED}ERROR: Library file not found: $lib_path${NC}"
        return 1
    fi
    
    # Key symbols we need to verify
    local required_symbols=(
        "gguf_type_name"
        "gguf_write_to_file"
        "ggml_view_1d"
        "ggml_view_2d"
        "ggml_view_3d"
        "ggml_view_4d"
        "ggml_new_tensor"
        "ggml_set_param"
    )
    
    local found_count=0
    local total_count=${#required_symbols[@]}
    
    echo "Required symbols check:"
    for symbol in "${required_symbols[@]}"; do
        if nm -g "$lib_path" 2>/dev/null | grep -q "$symbol"; then
            echo -e "  ✅ $symbol"
            ((found_count++))
        else
            echo -e "  ❌ $symbol"
        fi
    done
    
    echo -e "\nSymbol completeness: $found_count/$total_count"
    
    if [[ $found_count -eq $total_count ]]; then
        echo -e "${GREEN}✅ All required symbols found in $lib_name${NC}"
        return 0
    else
        echo -e "${RED}❌ Missing symbols in $lib_name${NC}"
        return 1
    fi
}

# Function to check all static libraries
check_all_libs() {
    local build_dir="$1"
    local all_passed=true
    
    echo -e "${YELLOW}=== Static Library Symbol Verification ===${NC}\n"
    
    # Check core libraries
    local libs=(
        "$build_dir/ggml/src/libggml.a"
        "$build_dir/src/libllama.a"
        "$build_dir/common/libcommon.a"
    )
    
    for lib in "${libs[@]}"; do
        if ! check_sym "$lib"; then
            all_passed=false
        fi
        echo ""
    done
    
    if $all_passed; then
        echo -e "${GREEN}🎉 All static libraries passed symbol verification!${NC}"
        echo -e "${GREEN}   Glue-code architecture should work correctly.${NC}"
        return 0
    else
        echo -e "${RED}💥 Some static libraries are missing required symbols!${NC}"
        echo -e "${RED}   Consider enabling OBJECT library fallback.${NC}"
        return 1
    fi
}

# Main execution
if [[ $# -eq 0 ]]; then
    # Default: check all libraries in standard build directory
    BUILD_DIR="${BUILD_DIR:-backend/llama.cpp/build}"
    check_all_libs "$BUILD_DIR"
elif [[ $# -eq 1 ]]; then
    if [[ -d "$1" ]]; then
        # Directory provided - check all libs in that directory
        check_all_libs "$1"
    else
        # Single library file provided
        check_sym "$1"
    fi
else
    echo "Usage: $0 [library_file_or_build_directory]"
    echo "Examples:"
    echo "  $0                                    # Check default build directory"
    echo "  $0 backend/llama.cpp/build           # Check specific build directory"
    echo "  $0 libggml.a                         # Check single library file"
    exit 1
fi 