// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_graphics>
#include <metal_matrix>
#include <metal_math>
using namespace metal;


/**
 Structure connecting the vertex shader to the fragment shader.
 */
struct VertexInOut
{
  float4 position [[position]];
};


/**
 Vertex shader.
 */
vertex VertexInOut testVertex(
    constant float2         *inPosition   [[ buffer(0) ]],
    uint                     id           [[ vertex_id ]])
{
  return { {inPosition[id].x, inPosition[id].y, 0.0, 1.0} };
}


/**
 Fragment shader.
 */
fragment half4 testFragment(
    VertexInOut     inFrag    [[ stage_in ]])
{
  return half4(1.0, 0.0, 0.0, 1.0);
}
