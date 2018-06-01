#ifndef ONEFLOW_CORE_ACTOR_EVALUATOR_MDUPDT_ACTOR_H_
#define ONEFLOW_CORE_ACTOR_EVALUATOR_MDUPDT_ACTOR_H_

#include "oneflow/core/actor/compute_actor.h"

namespace oneflow {

class EvalMdUpdtActor final : public CompActor {
 public:
  OF_DISALLOW_COPY_AND_MOVE(EvalMdUpdtActor);
  EvalMdUpdtActor() = default;
  ~EvalMdUpdtActor() = default;

 private:
  void VirtualCompActorInit(const TaskProto&) override;
  int HandlerInitModelAndConstModel(const ActorMsg&);
  int HandlerSendInitialModel(const ActorMsg&);
  int HandlerWaitToEnd(const ActorMsg&);
  void InitRegstBySendToFw(const int64_t regst_desc_id);

  int64_t model_regst_desc_id_;
  int64_t const_model_regst_desc_id_;
  int64_t related_init_model_actor_id_;
  int8_t init_remaining_cnt_;
  bool is_eof_;
};

}  // namespace oneflow

#endif  // ONEFLOW_CORE_ACTOR_EVALUATOR_MDUPDT_ACTOR_H_
