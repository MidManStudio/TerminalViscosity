// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon.vs"
// ============================================================================

#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexTangent; // the direction of the vertex from the middle of the balloon at rest

uniform mat4 mvp;

out vec3 fragPos;
out vec3 fragNormal;
out float fragKnot;
out vec3 fragDir;

// The balloon mesh is already in world space, so positions and normals pass
// straight through. The first texture coordinate carries how much of the knot
// a vertex is. The tangent carries the direction of the vertex from the middle of
// the balloon when it is at rest, which stays with the vertex as the balloon
// stretches, and is where the drawing is taken from.
void main()
{
    fragPos = vertexPosition;
    fragNormal = vertexNormal;
    fragKnot = vertexTexCoord.x;
    fragDir = vertexTangent.xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
