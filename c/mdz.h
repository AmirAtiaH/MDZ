#ifndef MDZ_H
#define MDZ_H

#ifdef _WIN32
    #ifdef MDZ_BUILD_DLL
        #define MDZ_API __declspec(dllexport)
    #else
        #define MDZ_API __declspec(dllimport)
    #endif
#else
    #define MDZ_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Compile an MDX string to a JSX module string.
// Returns 0 on success, -1 on error.
// On success, *output points to the result string (must be freed with mdz_free_string).
// On error, *error_msg points to the error message (must be freed with mdz_free_string).
MDZ_API int mdz_compile(const char* input, char** output, char** error_msg);

// Compile an MDX file to a JSX module string.
// Returns 0 on success, -1 on error.
// On success, *output points to the result string (must be freed with mdz_free_string).
// On error, *error_msg points to the error message (must be freed with mdz_free_string).
MDZ_API int mdz_compile_file(const char* path, char** output, char** error_msg);

// Free a string allocated by mdz.
MDZ_API void mdz_free_string(char* s);

#ifdef __cplusplus
}
#endif

#endif // MDZ_H
