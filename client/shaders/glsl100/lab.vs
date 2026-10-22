// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "lab.vs"
// ============================================================================

#version 100

attribute vec3 vertexPosition;
attribute vec2 vertexTexCoord;
attribute vec3 vertexNormal;
attribute vec4 vertexColor;

uniform mat4 mvp;

varying vec3 fragPos;
varying vec3 fragNormal;
varying vec4 fragColor;
varying vec2 fragMaterial;

// GLES 2 version of the glsl330 shader. Keep the two in step by hand.
void main()
{
    fragPos = vertexPosition;
    fragNormal = vertexNormal;
    fragColor = vertexColor;
    fragMaterial = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
