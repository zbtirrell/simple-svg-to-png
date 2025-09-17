//! # ResVG Bridge
//! 
//! A Rust library that provides a C-compatible FFI interface for rendering SVG files to RGBA pixel data.
//! This library acts as a bridge between C/C++ applications and the ResVG SVG rendering engine.
//! 
//! ## Key Features
//! - Thread-safe error handling using thread-local storage
//! - Memory-safe FFI with proper resource management
//! - High-quality SVG rendering with scaling support
//! - C-compatible data structures for easy integration

use std::{cell::RefCell, os::raw::c_char, slice};
use resvg::tiny_skia::{Pixmap, Transform};
use usvg::{self, Tree};

// ============================================================================
// ERROR HANDLING SYSTEM
// ============================================================================
// 
// This section implements thread-safe error handling for the FFI interface.
// We use thread-local storage to avoid race conditions when multiple threads
// call our functions concurrently.

// Thread-local storage for the last error message.
// Each thread maintains its own error state to prevent race conditions.
thread_local! {
    static LAST_ERR: RefCell<Option<String>> = RefCell::new(None);
}

/// Sets the current thread's error message.
/// This is used internally by all functions to report errors to C callers.
/// 
/// # Arguments
/// * `msg` - The error message to store
fn set_err(msg: String) {
    LAST_ERR.with(|e| *e.borrow_mut() = Some(msg));
}

/// Gets a pointer to the last error message for the current thread.
/// 
/// # Returns
/// * A pointer to a null-terminated C string containing the error message
/// * `std::ptr::null()` if no error occurred
/// 
/// # Safety
/// The returned pointer is valid until the next call to any function on this thread.
/// The caller should not free this pointer - it's managed by the thread-local storage.
#[no_mangle]
pub extern "C" fn rb_last_error() -> *const c_char {
    LAST_ERR.with(|e| {
        if let Some(s) = e.borrow().as_ref() {
            s.as_ptr() as *const c_char
        } else {
            std::ptr::null()
        }
    })
}

/// Copies the last error message into a caller-provided buffer.
/// This is a safer alternative to `rb_last_error()` as it avoids lifetime issues.
/// 
/// # Arguments
/// * `buf` - Pointer to the destination buffer (must not be null)
/// * `len` - Size of the destination buffer in bytes
/// 
/// # Returns
/// * Number of bytes written to the buffer (excluding null terminator)
/// * 0 if no error occurred or if buffer is null/empty
/// 
/// # Safety
/// The caller must ensure `buf` points to a valid buffer of at least `len` bytes.
/// The buffer will be null-terminated if there's space.
#[no_mangle]
pub extern "C" fn rb_last_error_copy(buf: *mut c_char, len: usize) -> usize {
    if buf.is_null() || len == 0 { return 0; }
    LAST_ERR.with(|e| {
        if let Some(s) = e.borrow().as_ref() {
            let bytes = s.as_bytes();
            let n = bytes.len().min(len - 1);
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, n);
                *buf.add(n) = 0; // Null terminate
            }
            n
        } else { 0 }
    })
}

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/// C-compatible structure representing a rendered image.
/// This structure is used to return RGBA pixel data from the rendering functions.
/// 
/// # Fields
/// * `ptr` - Pointer to the RGBA pixel data (owned by the library)
/// * `len` - Total number of bytes in the pixel data
/// * `width` - Width of the image in pixels
/// * `height` - Height of the image in pixels
/// 
/// # Memory Layout
/// The pixel data is stored as RGBA bytes in row-major order:
/// - Each pixel is 4 bytes (R, G, B, A)
/// - Total size = width * height * 4 bytes
/// - Row 0: [R0G0B0A0, R1G1B1A1, ..., R(width-1)G(width-1)B(width-1)A(width-1)]
/// - Row 1: [R0G0B0A0, R1G1B1A1, ..., R(width-1)G(width-1)B(width-1)A(width-1)]
/// - etc.
/// 
/// # Safety
/// The caller must call `rb_free_image()` to free the memory when done.
#[repr(C)]
pub struct RBImage {
    /// Pointer to the RGBA pixel data
    pub ptr: *mut u8,
    /// Total number of bytes in the pixel data
    pub len: usize,
    /// Width of the image in pixels
    pub width: u32,
    /// Height of the image in pixels
    pub height: u32,
}


// ============================================================================
// RENDERING FUNCTIONS
// ============================================================================

/// Renders an SVG file to RGBA pixel data.
/// 
/// This is the main function for converting SVG content to raster images.
/// The SVG is scaled to fit the requested dimensions while maintaining aspect ratio.
/// 
/// # Arguments
/// * `svg_ptr` - Pointer to the SVG data (must not be null)
/// * `svg_len` - Length of the SVG data in bytes
/// * `width` - Desired output width in pixels (must be > 0)
/// * `height` - Desired output height in pixels (must be > 0)
/// 
/// # Returns
/// * `RBImage` struct containing the rendered pixel data
/// * If an error occurs, returns an image with null pointer and zero dimensions
/// 
/// # Safety
/// The caller must ensure `svg_ptr` points to valid SVG data for `svg_len` bytes.
/// The returned image must be freed with `rb_free_image()` when no longer needed.
/// 
/// # Error Handling
/// Errors are stored in thread-local storage and can be retrieved with:
/// - `rb_last_error()` - Get pointer to error message
/// - `rb_last_error_copy()` - Copy error message to buffer
#[no_mangle]
pub extern "C" fn rb_render_svg_to_rgba(
    svg_ptr: *const u8,
    svg_len: usize,
    width: u32,
    height: u32,
) -> RBImage {
    // Clear any previous error for this thread
    LAST_ERR.with(|e| *e.borrow_mut() = None);

    // Validate input parameters
    if svg_ptr.is_null() || svg_len == 0 || width == 0 || height == 0 {
        set_err("invalid args".into());
        return RBImage { ptr: std::ptr::null_mut(), len: 0, width: 0, height: 0 };
    }

    // Convert raw pointer to byte slice
    let svg_bytes = unsafe { slice::from_raw_parts(svg_ptr, svg_len) };

    // Parse SVG content into a tree structure
    let opt = usvg::Options::default();
    let tree = match Tree::from_data(svg_bytes, &opt) {
        Ok(t) => t,
        Err(e) => {
            set_err(format!("parse error: {e}"));
            return RBImage { ptr: std::ptr::null_mut(), len: 0, width: 0, height: 0 };
        }
    };

    // Allocate target buffer for the rendered image
    let mut pixmap = match Pixmap::new(width, height) {
        Some(p) => p,
        None => {
            set_err("alloc pixmap failed".into());
            return RBImage { ptr: std::ptr::null_mut(), len: 0, width: 0, height: 0 };
        }
    };

    // Calculate scaling factors to fit SVG into requested dimensions
    let size = tree.size();
    let sx = width as f32 / size.width().max(1.0);
    let sy = height as f32 / size.height().max(1.0);
    let ts = Transform::from_scale(sx, sy);

    // Render the SVG tree to the pixmap
    resvg::render(&tree, ts, &mut pixmap.as_mut());

    // Extract pixel data and prepare for FFI return
    // We need to move the data to the heap and forget it so it doesn't get dropped
    let mut data = pixmap.take();
    let out = RBImage { 
        ptr: data.as_mut_ptr(), 
        len: data.len(), 
        width, 
        height 
    };
    std::mem::forget(data); // Prevent automatic deallocation
    out
}

/// Frees memory allocated for an RBImage.
/// 
/// This function must be called to free the memory allocated by `rb_render_svg_to_rgba()`.
/// Failing to call this function will result in a memory leak.
/// 
/// # Arguments
/// * `img` - The RBImage structure to free
/// 
/// # Safety
/// This function is safe to call multiple times on the same image (idempotent).
/// After calling this function, the image structure should not be used again.
/// 
/// # Example
/// ```c
/// RBImage img = rb_render_svg_to_rgba(svg_data, svg_len, 100, 100);
/// // Use the image...
/// rb_free_image(img);
/// ```
#[no_mangle]
pub extern "C" fn rb_free_image(img: RBImage) {
    // Only free if we have valid data
    if !img.ptr.is_null() && img.len > 0 {
        // Reconstruct the Vec to properly deallocate the memory
        // This is safe because we know the memory was allocated by Vec::from_raw_parts
        unsafe { 
            drop(Vec::from_raw_parts(img.ptr, img.len, img.len)) 
        };
    }
}
