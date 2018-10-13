#include <stddef.h>
#include <stdint.h>
#include <limits.h>
#include <cairo/cairo.h>
#include <emmintrin.h>
#include <smmintrin.h>

inline static uint32_t avg2(uint32_t a, uint32_t b)
{
    return (((a^b) & 0xfefefefeUL) >> 1) + (a&b);
}

inline static uint32_t avg4(const uint32_t* __restrict__ a, const uint32_t* __restrict__ b)
{
    return avg2(avg2(a[0], a[1]), avg2(b[0], b[1]));
}

static void scale_half_sse_argb32(unsigned char* __restrict__ dst, size_t dst_stride, unsigned char* __restrict__ src, size_t src_stride, unsigned width, unsigned height)
{
  unsigned width4 = width / 4;
  unsigned rest4 = width % 4;
  int use_streaming = (((intptr_t)src | src_stride) & 15) == 0 && __builtin_cpu_supports("sse4.1");
  for(unsigned y=0 ; y<height ; y++,dst+=dst_stride) {
    unsigned char* __restrict__ dst_row = dst;
    unsigned char* __restrict__ src_row0 = src; src += src_stride;
    unsigned char* __restrict__ src_row1 = src; src += src_stride;

    if(__builtin_expect(use_streaming, 1)) {
      for(unsigned x=0 ; x<width4 ; x++,dst_row+=16,src_row0+=32,src_row1+=32) {
        __m128i left  = _mm_avg_epu8(_mm_stream_load_si128((__m128i*)(src_row0   )), _mm_stream_load_si128((__m128i*)(src_row1   )));
        __m128i right = _mm_avg_epu8(_mm_stream_load_si128((__m128i*)(src_row0+16)), _mm_stream_load_si128((__m128i*)(src_row1+16)));
        __m128i t0 = _mm_unpacklo_epi32(left, right);
        __m128i t1 = _mm_unpackhi_epi32(left, right);
        __m128i shuffle1 = _mm_unpacklo_epi32(t0, t1);
        __m128i shuffle2 = _mm_unpackhi_epi32(t0, t1);
        _mm_store_si128((__m128i*)dst_row, _mm_avg_epu8(shuffle1, shuffle2));
      }
    } else {
      for(unsigned x=0 ; x<width4 ; x++,dst_row+=16,src_row0+=32,src_row1+=32) {
        __m128i left  = _mm_avg_epu8(_mm_loadu_si128((const __m128i*)(src_row0   )), _mm_loadu_si128((const __m128i*)(src_row1   )));
        __m128i right = _mm_avg_epu8(_mm_loadu_si128((const __m128i*)(src_row0+16)), _mm_loadu_si128((const __m128i*)(src_row1+16)));
        __m128i t0 = _mm_unpacklo_epi32(left, right);
        __m128i t1 = _mm_unpackhi_epi32(left, right);
        __m128i shuffle1 = _mm_unpacklo_epi32(t0, t1);
        __m128i shuffle2 = _mm_unpackhi_epi32(t0, t1);
        _mm_store_si128((__m128i*)dst_row, _mm_avg_epu8(shuffle1, shuffle2));
      }
    }
    switch(rest4) {
    case 3: *(uint32_t*)(dst_row+8) = avg4((const uint32_t*)(src_row0+16), (const uint32_t*)(src_row1+16));
    case 2: *(uint32_t*)(dst_row+4) = avg4((const uint32_t*)(src_row0+ 8), (const uint32_t*)(src_row1+ 8));
    case 1: *(uint32_t*)(dst_row+0) = avg4((const uint32_t*)(src_row0+ 0), (const uint32_t*)(src_row1+ 0));
    default: break;
    }
  }
}

static cairo_user_data_key_t aligned_surface_key;

static cairo_surface_t* create_surface_aligned(cairo_format_t format, int width, int height)
{
  cairo_surface_t* surface;
  void* data;
  int stride = cairo_format_stride_for_width(format, width);
  if(stride < 0 || stride > INT_MAX-15)
    return NULL;
  stride = (stride + 15) & ~15;
  if(height > INT_MAX / stride)
    return NULL;
  data = malloc(stride * height);
  if(!data)
    return NULL;
  surface = cairo_image_surface_create_for_data(data, format, width, height, stride);
  if(!surface) {
    free(data);
    return NULL;
  }
  cairo_surface_set_user_data(surface, &aligned_surface_key, data, free);
  return surface;
}

cairo_surface_t* puzzle_puzzle_area_scale_half (cairo_surface_t* surface)
{
  cairo_surface_t* result = NULL;
  cairo_format_t format = cairo_image_surface_get_format(surface);
  int width = cairo_image_surface_get_width(surface);
  int height = cairo_image_surface_get_height(surface);
  unsigned char* data = cairo_image_surface_get_data(surface);

  if(width < 2 || height < 2 || !data)
    return NULL;

  switch(format) {
  case CAIRO_FORMAT_ARGB32:
  case CAIRO_FORMAT_RGB24:
    result = create_surface_aligned(format, width >> 1, height >> 1);
    if(result) {
      scale_half_sse_argb32(cairo_image_surface_get_data(result), cairo_image_surface_get_stride(result),
                            data, cairo_image_surface_get_stride(surface), width >> 1, height >> 1);
      cairo_surface_mark_dirty(result);
    }
    break;

  default:
    break;
  }

  return result;
}

