/*
Copyright 2020 The OneFlow Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
#include "oneflow/core/framework/framework.h"
#include "oneflow/core/operator/reduce_sbp_util.h"

namespace oneflow {

REGISTER_USER_OP("reduce_sum_like")
    .Input("x")
    .Input("like")
    .Output("y")
    .Attr("axis", UserOpAttrType::kAtListInt32)
    .SetTensorDescInferFn([](user_op::InferContext* ctx) -> Maybe<void> {
      const user_op::TensorDesc* x_tensor = ctx->TensorDesc4ArgNameAndIndex("x", 0);
      const user_op::TensorDesc* like_tensor = ctx->TensorDesc4ArgNameAndIndex("like", 0);
      const auto& axis = ctx->Attr<std::vector<int32_t>>("axis");
      if (axis.empty()) { CHECK_EQ_OR_RETURN(x_tensor->shape(), like_tensor->shape()); }
      CHECK_EQ_OR_RETURN(x_tensor->data_type(), like_tensor->data_type());
      user_op::TensorDesc* y_tensor = ctx->TensorDesc4ArgNameAndIndex("y", 0);
      *y_tensor = *like_tensor;
      return Maybe<void>::Ok();
    })
    .SetBatchAxisInferFn([](user_op::BatchAxisContext* ctx) -> Maybe<void> {
      *ctx->BatchAxis4ArgNameAndIndex("y", 0) = *ctx->BatchAxis4ArgNameAndIndex("like", 0);
      return Maybe<void>::Ok();
    })
    .SetGetSbpFn([](user_op::SbpContext* ctx) -> Maybe<void> {
      int32_t num_axes = 0;
      HashSet<int32_t> conf_axes;
      {
        const auto& in_tensor = ctx->LogicalTensorDesc4InputArgNameAndIndex("x", 0);
        num_axes = in_tensor.shape().NumAxes();
        const auto& reduced_axes = ctx->Attr<std::vector<int32_t>>("axis");
        conf_axes = {reduced_axes.begin(), reduced_axes.end()};
      }
      auto IsReducedAxis = ReduceSbpUtil::MakePredicatorIsReducedAxis(conf_axes, num_axes);
      FOR_RANGE(int64_t, i, 0, num_axes) {
        if (IsReducedAxis(i)) {
          ctx->NewBuilder()
              .Split(user_op::OpArg("x", 0), i)
              .Broadcast(user_op::OpArg("like", 0))
              .PartialSum(user_op::OpArg("y", 0))
              .Build();
          ctx->NewBuilder()
              .Split(user_op::OpArg("x", 0), i)
              .PartialSum(user_op::OpArg("like", 0))
              .PartialSum(user_op::OpArg("y", 0))
              .Build();
        } else {
          ctx->NewBuilder().Split(ctx->inputs(), i).Split(ctx->outputs(), i).Build();
        }
        ctx->NewBuilder()
            .Broadcast(user_op::OpArg("x", 0))
            .PartialSum(user_op::OpArg("like", 0))
            .Broadcast(user_op::OpArg("y", 0))
            .Build();
      }
      return Maybe<void>::Ok();
    })
    .SetInputArgModifyFn([](user_op::GetInputArgModifier GetInputArgModifierFn,
                            const user_op::UserOpConfWrapper&) {
      user_op::InputArgModifier* like_arg_modifier = GetInputArgModifierFn("like", 0);
      CHECK(like_arg_modifier != nullptr);
      like_arg_modifier->set_use_header_only(true);
      like_arg_modifier->set_requires_grad(false);
    });

}  // namespace oneflow
