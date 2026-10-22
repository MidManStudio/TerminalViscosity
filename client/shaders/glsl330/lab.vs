// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "lab.vs"
// ============================================================================

#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;

uniform mat4 mvp;

out vec3 fragPos;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragMaterial;

// The room is one mesh already in world space, so positions and normals pass
// straight through. The texture coordinate carries how much a surface glows
// (x) and how glossy it is (y).
void main()
{
    fragPos = vertexPosition;
    fragNormal = vertexNormal;
    fragColor = vertexColor;
    fragMaterial = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
