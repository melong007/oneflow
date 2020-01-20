from __future__ import absolute_import

from functools import reduce
import operator

import oneflow as flow
import oneflow.python.framework.compile_context as compile_context
import oneflow.python.framework.remote_blob as remote_blob_util
import oneflow.python.framework.distribute as distribute_util
import oneflow.python.framework.id_util as id_util
import oneflow.core.operator.op_conf_pb2 as op_conf_util
import oneflow.core.register.logical_blob_id_pb2 as logical_blob_id_util

from oneflow.python.oneflow_export import oneflow_export


@oneflow_export('experimental.unique_with_counts')
def unique_with_counts(x, out_idx=flow.int32, name=None):
    op_conf = op_conf_util.OperatorConf()
    if name is None:
        op_conf.name = id_util.UniqueStr('UniqueWithCounts_')
    else:
        op_conf.name = name

    op_conf.unique_with_counts_conf.x = x.logical_blob_name
    op_conf.unique_with_counts_conf.y = 'y'
    op_conf.unique_with_counts_conf.idx = 'idx'
    op_conf.unique_with_counts_conf.count = 'count'
    op_conf.unique_with_counts_conf.num_unique = 'num_unique'
    op_conf.unique_with_counts_conf.out_idx = out_idx

    compile_context.CurJobAddOp(op_conf)
    y_lbi = logical_blob_id_util.LogicalBlobId()
    y_lbi.op_name = op_conf.name
    y_lbi.blob_name = 'y'
    idx_lbi = logical_blob_id_util.LogicalBlobId()
    idx_lbi.op_name = op_conf.name
    idx_lbi.blob_name = 'idx'
    count_lbi = logical_blob_id_util.LogicalBlobId()
    count_lbi.op_name = op_conf.name
    count_lbi.blob_name = 'count'
    num_unique_lbi = logical_blob_id_util.LogicalBlobId()
    num_unique_lbi.op_name = op_conf.name
    num_unique_lbi.blob_name = 'num_unique'

    return (
            remote_blob_util.RemoteBlob(y_lbi),
            remote_blob_util.RemoteBlob(idx_lbi),
            remote_blob_util.RemoteBlob(count_lbi),
            remote_blob_util.RemoteBlob(num_unique_lbi),
        )
