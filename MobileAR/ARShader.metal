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
vertex VertexInOut texturedQuadVertex(
    constant float4         *pPosition   [[ buffer(0) ]],
    constant float4x4       *pMVP        [[ buffer(1) ]],
    uint                     vid         [[ vertex_id ]])
{
  return { *pMVP * pPosition[vid] };
}


/**
 Fragment shader.
 */
fragment half4 texturedQuadFragment(
    VertexInOut     inFrag    [[ stage_in ]])
{
  return half4(1.0, 0.0, 0.0, 1.0);
}
