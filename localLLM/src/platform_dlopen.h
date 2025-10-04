// --- FILE: localLLM/src/platform_dlopen.h ---
// Cross-platform dynamic library loading wrapper
// Provides unified interface for POSIX dlopen and Windows LoadLibrary

#pragma once

#ifdef _WIN32
    #include <windows.h>
    #include <cstdio>
    typedef HMODULE platform_dlhandle_t;
    #define PLATFORM_RTLD_DEFAULT NULL
    #define PLATFORM_RTLD_LAZY 0
    #define PLATFORM_RTLD_GLOBAL 0
#else
    #include <dlfcn.h>
    typedef void* platform_dlhandle_t;
    #define PLATFORM_RTLD_DEFAULT RTLD_DEFAULT
    #define PLATFORM_RTLD_LAZY RTLD_LAZY
    #define PLATFORM_RTLD_GLOBAL RTLD_GLOBAL
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Cross-platform dlopen wrapper
platform_dlhandle_t platform_dlopen(const char* filename, int flags);

// Cross-platform dlsym wrapper
void* platform_dlsym(platform_dlhandle_t handle, const char* symbol);

// Cross-platform dlerror wrapper
const char* platform_dlerror(void);

// Cross-platform dlclose wrapper
int platform_dlclose(platform_dlhandle_t handle);

#ifdef __cplusplus
}
#endif

// Implementation section
#ifdef _WIN32

// Windows implementation using Win32 API
inline platform_dlhandle_t platform_dlopen(const char* filename, int flags) {
    (void)flags; // Ignore flags parameter on Windows
    if (filename == NULL) {
        return GetModuleHandle(NULL); // Equivalent to RTLD_DEFAULT
    }
    return LoadLibraryA(filename);
}

inline void* platform_dlsym(platform_dlhandle_t handle, const char* symbol) {
    return (void*)GetProcAddress(handle, symbol);
}

inline const char* platform_dlerror(void) {
    static char error_buffer[256];
    DWORD error_code = GetLastError();
    if (error_code == 0) {
        return NULL;
    }
    
    DWORD result = FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        error_code,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        error_buffer,
        sizeof(error_buffer) - 1,
        NULL
    );
    
    if (result == 0) {
        snprintf(error_buffer, sizeof(error_buffer), "Windows error code: %lu", error_code);
    }
    
    return error_buffer;
}

inline int platform_dlclose(platform_dlhandle_t handle) {
    return FreeLibrary(handle) ? 0 : -1;
}

#else

// POSIX implementation (Linux, macOS, etc.)
inline platform_dlhandle_t platform_dlopen(const char* filename, int flags) {
    return dlopen(filename, flags);
}

inline void* platform_dlsym(platform_dlhandle_t handle, const char* symbol) {
    return dlsym(handle, symbol);
}

inline const char* platform_dlerror(void) {
    return dlerror();
}

inline int platform_dlclose(platform_dlhandle_t handle) {
    return dlclose(handle);
}

#endif
