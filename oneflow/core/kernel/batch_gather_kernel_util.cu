#include "oneflow/core/kernel/batch_gather_kernel_util.h"
#include "oneflow/core/kernel/kernel_util.cuh"
#include <assert.h>

namespace oneflow {

namespace {

template<typename K>
__device__ int64_t GetInOffset(const int64_t out_offset, const K* indices,
                               const int64_t indices_num, const int64_t instance_size,
                               const int64_t gather_dim_size) {
  const int64_t batch_idx = out_offset / (indices_num * instance_size);
  const int64_t indices_idx = out_offset % (indices_num * instance_size) / instance_size;
  const int64_t inner_idx = out_offset % instance_size;
  const int64_t idx = indices[batch_idx * indices_num + indices_idx];
  assert(idx >= 0 && idx < gather_dim_size);
  return batch_idx * gather_dim_size * instance_size + idx * instance_size + inner_idx;
}

template<typename T, typename K>
__global__ void BatchGatherForwardGpu(const int64_t elem_cnt, const T* in, const K* indices,
                                      const int64_t indices_num, const int64_t instance_size,
                                      const int64_t gather_dim_size, T* out) {
  CUDA_1D_KERNEL_LOOP(i, elem_cnt) {
    out[i] = in[GetInOffset<K>(i, indices, indices_num, instance_size, gather_dim_size)];
  }
}

template<typename T, typename K>
__global__ void BatchGatherForwardGpuV2(const int64_t batch_num, const int64_t indices_num,
                                        const int64_t gather_dim_size, const int64_t instance_size,
                                        const K* indices, const T* in, T* out) {
#define SHARED_BUF_NAME buf_##T
  extern __shared__ T SHARED_BUF_NAME[];
  const int64_t out_batch_instance_size = gather_dim_size * instance_size;
  const int64_t in_batch_instance_size = indices_num * instance_size;
  for (int32_t batch_idx = blockIdx.x; batch_idx < batch_num; batch_idx += gridDim.x) {
    const K* batch_indices = indices + batch_idx * indices_num;
    const T* batch_in = in + batch_idx * in_batch_instance_size;
    T* batch_out = out + batch_idx * out_batch_instance_size;
    for (int32_t i = threadIdx.x; i < out_batch_instance_size; i += blockDim.x) {
      SHARED_BUF_NAME[i] = 0;
    }
    __syncthreads();
    for (int32_t i = threadIdx.x; i < in_batch_instance_size; i += blockDim.x) {
      gpu_atomic_add(SHARED_BUF_NAME + batch_indices[i / instance_size], batch_in[i]);
    }
    __syncthreads();
    for (int32_t i = threadIdx.x; i < out_batch_instance_size; i += blockDim.x) {
      batch_out[i] = SHARED_BUF_NAME[i];
    }
  }
}

template<typename T, typename K>
__global__ void BatchGatherBackwardGpu(const int64_t elem_cnt, const T* out_diff, const K* indices,
                                       const int64_t indices_num, const int64_t instance_size,
                                       const int64_t gather_dim_size, T* in_diff) {
  CUDA_1D_KERNEL_LOOP(i, elem_cnt) {
    const T diff_val = out_diff[i];
    if (diff_val != static_cast<T>(0)) {
      gpu_atomic_add(
          in_diff + GetInOffset<K>(i, indices, indices_num, instance_size, gather_dim_size),
          diff_val);
    }
  }
}

}  // namespace

template<typename T, typename K>
struct BatchGatherKernelUtilImpl<DeviceType::kGPU, T, K> final {
  static void Forward(DeviceCtx* ctx, const T* in, const K* indices, const Shape& flat_out_shape,
                      const int64_t gather_dim_size, T* out);
  static void Backward(DeviceCtx* ctx, const T* out_diff, const K* indices,
                       const Shape& flat_out_diff_shape, const int64_t gather_dim_size, T* in_diff);
};

template<typename T, typename K>
void BatchGatherKernelUtilImpl<DeviceType::kGPU, T, K>::Forward(DeviceCtx* ctx, const T* in,
                                                                const K* indices,
                                                                const Shape& flat_out_shape,
                                                                const int64_t gather_dim_size,
                                                                T* out) {
  const int64_t batch_num = flat_out_shape.At(0);
  const int64_t indices_num = flat_out_shape.At(1);
  const int64_t instance_size = flat_out_shape.At(2);
  const size_t out_batch_size_bytes = instance_size * gather_dim_size * sizeof(T);
  if (batch_num >= 256 && out_batch_size_bytes <= 16 * 1024 && indices_num * instance_size >= 256) {
    BatchGatherForwardGpuV2<T, K><<<256, 1024, out_batch_size_bytes, ctx->cuda_stream()>>>(
        batch_num, indices_num, gather_dim_size, instance_size, indices, in, out);

  } else {
    const int64_t elem_cnt = batch_num * indices_num * instance_size;
    BatchGatherForwardGpu<T, K>
        <<<BlocksNum4ThreadsNum(elem_cnt), kCudaThreadsNumPerBlock, 0, ctx->cuda_stream()>>>(
            elem_cnt, in, indices, indices_num, instance_size, gather_dim_size, out);
  }
}

template<typename T, typename K>
void BatchGatherKernelUtilImpl<DeviceType::kGPU, T, K>::Backward(DeviceCtx* ctx, const T* out_diff,
                                                                 const K* indices,
                                                                 const Shape& flat_out_diff_shape,
                                                                 const int64_t gather_dim_size,
                                                                 T* in_diff) {
  const int64_t batch_num = flat_out_diff_shape.At(0);
  const int64_t indices_num = flat_out_diff_shape.At(1);
  const int64_t instance_size = flat_out_diff_shape.At(2);
  const int64_t elem_cnt = batch_num * indices_num * instance_size;

  BatchGatherBackwardGpu<T, K>
      <<<BlocksNum4ThreadsNum(elem_cnt), kCudaThreadsNumPerBlock, 0, ctx->cuda_stream()>>>(
          elem_cnt, out_diff, indices, indices_num, instance_size, gather_dim_size, in_diff);
}

#define INSTANTIATE_BATCH_GATHER_KERNEL_UTIL_IMPL_GPU(in_type_pair, index_type_pair)          \
  template struct BatchGatherKernelUtilImpl<DeviceType::kGPU, OF_PP_PAIR_FIRST(in_type_pair), \
                                            OF_PP_PAIR_FIRST(index_type_pair)>;
OF_PP_SEQ_PRODUCT_FOR_EACH_TUPLE(INSTANTIATE_BATCH_GATHER_KERNEL_UTIL_IMPL_GPU,
                                 FLOATING_DATA_TYPE_SEQ, INT_DATA_TYPE_SEQ);
#undef INSTANTIATE_BATCH_GATHER_KERNEL_UTIL_IMPL_GPU

}  // namespace oneflow
