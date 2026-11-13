#include "RenderBlend.h"

// x / 255 rounded to nearest, exact for every product of two bytes.
static inline uint32_t div255(uint32_t x) {
    x += 128;
    return (x + (x >> 8)) >> 8;
}

void ass_blend_image_into_tile(uint8_t *tile, ptrdiff_t tile_stride, int tile_x, int tile_y,
                               const ASS_Image *image, uint32_t color) {
    const uint32_t opacity = 255 - (color & 0xFF);
    if (opacity == 0 || image->w <= 0 || image->h <= 0) return;

    const uint32_t r = color >> 24;
    const uint32_t g = (color >> 16) & 0xFF;
    const uint32_t b = (color >> 8) & 0xFF;
    const int w = image->w;

    uint8_t *row = tile + (ptrdiff_t)(image->dst_y - tile_y) * tile_stride + (ptrdiff_t)(image->dst_x - tile_x) * 4;
    const uint8_t *coverage = image->bitmap;

    for (int y = 0; y < image->h; y++, row += tile_stride, coverage += image->stride) {
        // Branch-free so the loop vectorises: a zero-coverage pixel leaves the destination as it was.
        for (int x = 0; x < w; x++) {
            const uint32_t k = div255((uint32_t)coverage[x] * opacity);
            const uint32_t keep = 255 - k;
            uint8_t *px = row + x * 4;
            px[0] = (uint8_t)div255(b * k + px[0] * keep);
            px[1] = (uint8_t)div255(g * k + px[1] * keep);
            px[2] = (uint8_t)div255(r * k + px[2] * keep);
            px[3] = (uint8_t)(k + div255(px[3] * keep));
        }
    }
}
