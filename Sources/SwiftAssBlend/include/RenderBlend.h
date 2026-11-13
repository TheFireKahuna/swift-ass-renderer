#ifndef RENDER_BLEND_H
#define RENDER_BLEND_H

#include <stddef.h>
#include <stdint.h>
#include <libass/ass/ass.h>
#include <libass/ass/ass_types.h>

/// Composites one libass image over a tile of premultiplied BGRA pixels (byte order B, G, R, A).
///
/// `tile` points at the tile's top-left pixel; `tile_x` / `tile_y` are that pixel's canvas position, and the
/// image must lie inside the tile. `color` is libass's RRGGBBTT (TT = transparency), already converted to the
/// colours the video is displayed in.
void ass_blend_image_into_tile(uint8_t *tile, ptrdiff_t tile_stride, int tile_x, int tile_y,
                               const ASS_Image *image, uint32_t color);

#endif
