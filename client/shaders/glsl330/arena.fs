// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "arena.fs"
// ============================================================================

#version 330

in vec3 fragPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragMaterial;

uniform vec3 eyePos;
uniform vec4 blastPos;   // xyz: where the flash is, w: how far it reaches. Zero reach when there is none.
uniform vec4 blastColor; // rgb: its color, a: how bright it is now

// How much a blast lights a point of the room: the flash falls off with the
// square of the distance left to its edge. Zero when no blast is going.
vec3 blastGlow(vec3 p)
{
    float reach = clamp(1.0 - length(p - blastPos.xyz) / max(blastPos.w, 0.001), 0.0, 1.0);
    return blastColor.rgb * (blastColor.a * reach * reach);
}

out vec4 finalColor;

const vec3 fogColor = vec3(0.60, 0.76, 0.92);

// The coliseum is open to the sky. Shading is the lab's: a ground-and-sky ambient term, a
// key light that is now the sun, full brightness for anything emissive, a sheen on
// glossy surfaces, and a haze that starts far out so the stands stay in view.
void main()
{
    vec3 n = normalize(fragNormal);
    vec3 v = normalize(eyePos - fragPos);
    float sky = n.y * 0.5 + 0.5;
    vec3 ambient = mix(vec3(0.46, 0.43, 0.40), vec3(0.78, 0.82, 0.90), sky);
    float key = max(dot(n, normalize(vec3(0.45, 1.0, 0.25))), 0.0);

    vec3 base = fragColor.rgb;
    vec3 lit = base * (ambient + 0.55 * key);
    lit = mix(lit, base * 1.15, fragMaterial.x);

    float slant = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
    lit += fragMaterial.y * (0.10 + 0.55 * slant) * vec3(0.78, 0.86, 0.95);

    lit += blastGlow(fragPos);

    float fog = clamp((length(eyePos - fragPos) - 45.0) / 110.0, 0.0, 1.0);
    finalColor = vec4(mix(clamp(lit, 0.0, 1.0), fogColor, fog), 1.0);
}
