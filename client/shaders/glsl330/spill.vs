// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "spill.vs"
// ============================================================================

#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

uniform mat4 mvp;

out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragWorld;

// The quads of puddles and beads are made by the batch renderer already in world space, so the position passes
// straight through to the fragment shader, which uses it for the grain of the dissolve.
void main()
{
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    fragWorld = vertexPosition;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
