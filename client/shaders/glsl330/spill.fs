// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "spill.fs"
// ============================================================================

#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragWorld;

out vec4 finalColor;

// A puddle or a bead, drawn as a quad. The texture coordinate runs from -1 to 1 across it. A bead has 10 added to
// its x, so that one shader draws both. The color is the liquid's, and for a puddle its alpha is how much of it
// is left: 1 while it lies, then down to 0 as it dissolves.

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main()
{
    bool bead = fragTexCoord.x > 5.0;
    vec2 q = bead ? fragTexCoord - vec2(10.0, 0.0) : fragTexCoord;
    float d = length(q);
    if (bead) {
        // A ball lit from above and to one side, with a highlight and a brighter edge.
        if (d > 1.0) discard;
        vec3 n = vec3(q.x, q.y, sqrt(max(1.0 - d * d, 0.0)));
        vec3 light = normalize(vec3(-0.35, 0.6, 0.7));
        float diffuse = 0.55 + 0.45 * max(dot(n, light), 0.0);
        float spec = pow(max(dot(n, normalize(light + vec3(0.0, 0.0, 1.0))), 0.0), 18.0) * 0.8;
        float rim = pow(1.0 - n.z, 3.0) * 0.3;
        finalColor = vec4(fragColor.rgb * diffuse + spec + rim, fragColor.a * (1.0 - smoothstep(0.88, 1.0, d)));
        return;
    }
    // The edge of a puddle wanders, by a pattern that is different where it lies, and is the same all the way
    // round, since it is read off a circle.
    vec2 dir = q / max(d, 0.0001);
    float edge = 0.68 + 0.32 * vnoise(dir * 1.7 + fragWorld.xz * 6.0);
    float r = d / edge;
    if (r > 1.0) discard;
    // Dissolving takes away specks, the edge first, until none are left.
    float dissolve = 1.0 - fragColor.a;
    float grain = vnoise(fragWorld.xz * 70.0) * 0.6 + vnoise(fragWorld.xz * 26.0 + 5.0) * 0.4;
    if (grain * 0.75 + (1.0 - r) * 0.25 < dissolve) discard;
    // A flat sheet: a little darker in the middle, a bright line at the edge, and a glint.
    float body = 0.82 + 0.18 * r;
    float line = smoothstep(0.78, 0.92, r) * (1.0 - smoothstep(0.92, 1.0, r));
    float glint = pow(max(1.0 - length(q - vec2(-0.35, 0.3)) * 1.5, 0.0), 2.0) * 0.4;
    vec3 col = fragColor.rgb * body + line * 0.35 + glint;
    float alpha = 0.8 * (1.0 - smoothstep(0.93, 1.0, r)) * (1.0 - 0.35 * dissolve);
    finalColor = vec4(col, alpha);
}
