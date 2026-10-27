// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon.fs"
// ============================================================================

#version 330

in vec3 fragPos;
in vec3 fragNormal;
in float fragKnot;

uniform vec3 eyePos;
uniform vec3 lightDir;
uniform vec3 tint;
uniform float backFace;
uniform float strain; // 0 for a slack balloon, 1 at the point where it bursts

out vec4 finalColor;

// Latex over water. The balloon is drawn twice: first its inside (backFace is
// 1), then its outside. Shading is a soft diffuse term, a sharp highlight, and
// a reflection of a fake sky that gets stronger toward the edge of the shape,
// where the rubber is seen at a slant.
void main()
{
    vec3 n = normalize(fragNormal);
    if (backFace > 0.5) n = -n;
    vec3 v = normalize(eyePos - fragPos);
    float facing = clamp(dot(n, v), 0.0, 1.0);
    float rim = pow(1.0 - facing, 3.0);

    float diffuse = clamp(dot(n, lightDir) * 0.5 + 0.5, 0.0, 1.0);
    vec3 h = normalize(lightDir + v);
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 28.0);

    vec3 r = reflect(-v, n);
    float sky = smoothstep(-0.3, 0.7, r.y);
    vec3 env = mix(vec3(0.10, 0.12, 0.17), vec3(0.65, 0.78, 0.95), sky);

    vec3 liquid = tint * (0.30 + 0.70 * diffuse);
    vec3 color = liquid + env * (0.10 + 0.55 * rim) + vec3(spec * 0.42);
    float alpha = mix(0.55, 0.95, rim);

    // The knot is opaque, darker rubber.
    vec3 rubber = tint * 0.7 * (0.35 + 0.65 * diffuse) + env * 0.10 + vec3(spec * 0.3);
    color = mix(color, rubber, fragKnot);
    alpha = mix(alpha, 1.0, fragKnot);

    // Stretched rubber goes thin and pale, so a balloon near its limit looks it.
    float thin = strain * (1.0 - fragKnot);
    alpha *= 1.0 - 0.45 * thin;
    color += vec3(0.28) * thin * (0.5 + rim);

    if (backFace > 0.5) {
        color *= 0.55;
        alpha *= 0.8;
    }
    finalColor = vec4(color, alpha);
}
