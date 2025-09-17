#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * C-compatible structure representing a rendered image.
 * This structure is used to return RGBA pixel data from the rendering functions.
 *
 * # Fields
 * * `ptr` - Pointer to the RGBA pixel data (owned by the library)
 * * `len` - Total number of bytes in the pixel data
 * * `width` - Width of the image in pixels
 * * `height` - Height of the image in pixels
 *
 * # Memory Layout
 * The pixel data is stored as RGBA bytes in row-major order:
 * - Each pixel is 4 bytes (R, G, B, A)
 * - Total size = width * height * 4 bytes
 * - Row 0: [R0G0B0A0, R1G1B1A1, ..., R(width-1)G(width-1)B(width-1)A(width-1)]
 * - Row 1: [R0G0B0A0, R1G1B1A1, ..., R(width-1)G(width-1)B(width-1)A(width-1)]
 * - etc.
 *
 * # Safety
 * The caller must call `rb_free_image()` to free the memory when done.
 */
typedef struct RBImage {
  /**
   * Pointer to the RGBA pixel data
   */
  uint8_t *ptr;
  /**
   * Total number of bytes in the pixel data
   */
  uintptr_t len;
  /**
   * Width of the image in pixels
   */
  uint32_t width;
  /**
   * Height of the image in pixels
   */
  uint32_t height;
} RBImage;

/**
 * Gets a pointer to the last error message for the current thread.
 *
 * # Returns
 * * A pointer to a null-terminated C string containing the error message
 * * `std::ptr::null()` if no error occurred
 *
 * # Safety
 * The returned pointer is valid until the next call to any function on this thread.
 * The caller should not free this pointer - it's managed by the thread-local storage.
 */
const char *rb_last_error(void);

/**
 * Copies the last error message into a caller-provided buffer.
 * This is a safer alternative to `rb_last_error()` as it avoids lifetime issues.
 *
 * # Arguments
 * * `buf` - Pointer to the destination buffer (must not be null)
 * * `len` - Size of the destination buffer in bytes
 *
 * # Returns
 * * Number of bytes written to the buffer (excluding null terminator)
 * * 0 if no error occurred or if buffer is null/empty
 *
 * # Safety
 * The caller must ensure `buf` points to a valid buffer of at least `len` bytes.
 * The buffer will be null-terminated if there's space.
 */
uintptr_t rb_last_error_copy(char *buf, uintptr_t len);

/**
 * Renders an SVG file to RGBA pixel data.
 *
 * This is the main function for converting SVG content to raster images.
 * The SVG is scaled to fit the requested dimensions while maintaining aspect ratio.
 *
 * # Arguments
 * * `svg_ptr` - Pointer to the SVG data (must not be null)
 * * `svg_len` - Length of the SVG data in bytes
 * * `width` - Desired output width in pixels (must be > 0)
 * * `height` - Desired output height in pixels (must be > 0)
 *
 * # Returns
 * * `RBImage` struct containing the rendered pixel data
 * * If an error occurs, returns an image with null pointer and zero dimensions
 *
 * # Safety
 * The caller must ensure `svg_ptr` points to valid SVG data for `svg_len` bytes.
 * The returned image must be freed with `rb_free_image()` when no longer needed.
 *
 * # Error Handling
 * Errors are stored in thread-local storage and can be retrieved with:
 * - `rb_last_error()` - Get pointer to error message
 * - `rb_last_error_copy()` - Copy error message to buffer
 */
struct RBImage rb_render_svg_to_rgba(const uint8_t *svg_ptr,
                                     uintptr_t svg_len,
                                     uint32_t width,
                                     uint32_t height);

/**
 * Frees memory allocated for an RBImage.
 *
 * This function must be called to free the memory allocated by `rb_render_svg_to_rgba()`.
 * Failing to call this function will result in a memory leak.
 *
 * # Arguments
 * * `img` - The RBImage structure to free
 *
 * # Safety
 * This function is safe to call multiple times on the same image (idempotent).
 * After calling this function, the image structure should not be used again.
 *
 * # Example
 * ```c
 * RBImage img = rb_render_svg_to_rgba(svg_data, svg_len, 100, 100);
 * // Use the image...
 * rb_free_image(img);
 * ```
 */
void rb_free_image(struct RBImage img);
