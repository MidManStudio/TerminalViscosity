// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon.vs"
// ============================================================================

#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;

uniform mat4 mvp;

out vec3 fragPos;
out vec3 fragNormal;
out float fragKnot;

// The balloon mesh is already in world space, so positions and normals pass
// straight through. The first texture coordinate carries how much of the knot
// a vertex is.
void main()
{
    fragPos = vertexPosition;
    fragNormal = vertexNormal;
    fragKnot = vertexTexCoord.x;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
