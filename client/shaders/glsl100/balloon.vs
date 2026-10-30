// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon.vs"
// ============================================================================

#version 100

attribute vec3 vertexPosition;
attribute vec2 vertexTexCoord;
attribute vec3 vertexNormal;
attribute vec4 vertexTangent; // the direction of the vertex from the middle of the balloon at rest

uniform mat4 mvp;

varying vec3 fragPos;
varying vec3 fragNormal;
varying float fragKnot;
varying vec3 fragDir;

// GLES 2 version of the glsl330 shader. Keep the two in step by hand.
void main()
{
    fragPos = vertexPosition;
    fragNormal = vertexNormal;
    fragKnot = vertexTexCoord.x;
    fragDir = vertexTangent.xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
