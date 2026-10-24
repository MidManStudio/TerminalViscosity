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
uniform mat4 matModel;

out vec3 fragPos;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragMaterial;

// The room is one mesh already in world space, drawn with an identity model
// matrix, so positions and normals pass straight through. Vessels and hands are
// drawn with a model matrix that moves them, and it is applied here so the
// lighting and fog see world positions. The matrix only turns and moves, and
// the box faces it scales have axis-aligned normals, so a normal needs no
// special treatment. The texture coordinate carries how much a surface glows
// (x) and how glossy it is (y).
void main()
{
    fragPos = (matModel * vec4(vertexPosition, 1.0)).xyz;
    fragNormal = (matModel * vec4(vertexNormal, 0.0)).xyz;
    fragColor = vertexColor;
    fragMaterial = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
