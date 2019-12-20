#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <limits.h>
#include <gdk/gdk.h>
#include <emmintrin.h>
#include <smmintrin.h>

static inline __m128i squaredDifference(__m128i a, __m128i b)
{
    const __m128i K_1FF = _mm_set1_epi16(0x1FF);
    const __m128i lo = _mm_maddubs_epi16(_mm_unpacklo_epi8(a, b), K_1FF);
    const __m128i hi = _mm_maddubs_epi16(_mm_unpackhi_epi8(a, b), K_1FF);
    return _mm_add_epi32(_mm_madd_epi16(lo, lo), _mm_madd_epi16(hi, hi));
}

static inline __m128i horizontalSum32(__m128i a)
{
    const __m128i Z = _mm_setzero_si128();
    return _mm_add_epi64(_mm_unpacklo_epi32(a, Z), _mm_unpackhi_epi32(a, Z));
}

static inline uint64_t extractSum64(__m128i a)
{
    uint64_t tmp[2] __attribute__ ((aligned(16)));
    _mm_storeu_si128((__m128i*)tmp, a);
    return tmp[0] + tmp[1];
}

static uint64_t compare_rows(const unsigned char* __restrict__ src0, const unsigned char* __restrict__ src1, unsigned bytes)
{
    unsigned bytes16 = bytes / 16;
    unsigned rest16 = bytes % 16;
    int use_streaming = (((intptr_t)src0 | (intptr_t)src1) & 15) == 0 && __builtin_cpu_supports("sse4.1");
    __m128i sse_sum = _mm_setzero_si128();
    if(__builtin_expect(use_streaming, 1)) {
        for(unsigned x=0 ; x<bytes16 ; x++,src0+=16,src1+=16) {
            const __m128i a = _mm_stream_load_si128((__m128i*)src0);
            const __m128i b = _mm_stream_load_si128((__m128i*)src1);
            sse_sum = _mm_add_epi32(sse_sum, squaredDifference(a, b));
        }
    } else {
        for(unsigned x=0 ; x<bytes16 ; x++,src0+=16,src1+=16) {
            const __m128i a = _mm_loadu_si128((const __m128i*)src0);
            const __m128i b = _mm_loadu_si128((const __m128i*)src1);
            sse_sum = _mm_add_epi32(sse_sum, squaredDifference(a, b));
        }
    }
    uint64_t sum = extractSum64(horizontalSum32(sse_sum));
    for(unsigned x=0 ; x<rest16 ; x++) {
        int d = *src0++ - *src1++;
        sum += d * d;
    }
    return sum;
}

uint64_t puzzle_window_compare_rows(GdkPixbuf *pixbuf, unsigned row0, unsigned row1)
{
    int n_channels = gdk_pixbuf_get_n_channels(pixbuf);
    int width = gdk_pixbuf_get_width(pixbuf);
    int height = gdk_pixbuf_get_height(pixbuf);
    int stride = gdk_pixbuf_get_rowstride(pixbuf);
    const unsigned char* data = gdk_pixbuf_read_pixels(pixbuf);

    //printf("width=%d height=%d n_channels=%d stride=%d data=%p row0=%u row1=%u\n", width, height, n_channels, stride, data, row0, row1);
    if(width < 1 || row0 >= height || row1 >= height || !data)
        return ~0uLL;

    if(row0 == row1)
        return 0uLL;

    return compare_rows(data + row0 * stride, data + row1 * stride, width * n_channels);
}

static uint64_t compare_columns(const unsigned char* __restrict__ src0, const unsigned char* __restrict__ src1, unsigned n_channels, unsigned height, unsigned stride)
{
    uint64_t sum = 0;
    for(unsigned y=0 ; y<height ; y++,src0+=stride,src1+=stride) {
        unsigned row_sum = 0;
        for(unsigned x=0 ; x<n_channels ; x++) {
            int d = src0[x] - src1[x];
            row_sum += d * d;
        }
        sum += row_sum;
    }
    return sum;
}

uint64_t puzzle_window_compare_columns(GdkPixbuf *pixbuf, unsigned col0, unsigned col1, unsigned y0, unsigned y1)
{
    int n_channels = gdk_pixbuf_get_n_channels(pixbuf);
    int width = gdk_pixbuf_get_width(pixbuf);
    int height = gdk_pixbuf_get_height(pixbuf);
    int stride = gdk_pixbuf_get_rowstride(pixbuf);
    const unsigned char* data = gdk_pixbuf_read_pixels(pixbuf);

    //printf("width=%d height=%d n_channels=%d stride=%d data=%p row0=%u row1=%u\n", width, height, n_channels, stride, data, row0, row1);
    if(y0 >= y1 || y1 > height || col0 >= width || col1 >= width || !data)
        return ~0uLL;

    if(col0 == col1)
        return 0uLL;

    return compare_columns(data + y0 * stride + col0 * n_channels, data + y0 * stride + col1 * n_channels, n_channels, y1 - y0, stride);
}

