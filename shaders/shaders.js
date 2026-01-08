const vertexShaderSource = `
    attribute vec4 aVertexPosition;
    uniform mat4 uModelViewMatrix;
    uniform mat4 uProjectionMatrix;

    varying vec2 vPosition;

    void main() {
        gl_Position = uProjectionMatrix * uModelViewMatrix * aVertexPosition;
        vPosition = aVertexPosition.xy;
    }
`;

const fragmentShaderSource = `
    precision mediump float;

    uniform vec4 uColor;
    uniform float uOpacity;
    uniform float uBlurFactor;

    varying vec2 vPosition;

    float random(vec2 st) {
        return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
    }

    float roundedBoxSDF(vec2 p, vec2 b, float r) {
        vec2 q = abs(p) - b + vec2(r);
        return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
    }

    void main() {
        vec2 p = vPosition;

        float boxSize = 0.7;
        float cornerRadius = 0.19;

        float dist = roundedBoxSDF(p, vec2(boxSize), cornerRadius);

        float blurIntensity = uBlurFactor * uBlurFactor;

        float alpha;
        if (uBlurFactor < 0.3) {
            float edgeWidth = mix(0.05, 0.2, uBlurFactor);
            alpha = (1.0 - smoothstep(-edgeWidth, edgeWidth * 0.5, dist)) * uOpacity;
        } else {
            float gaussianRadius = mix(0.6, 1.4, (uBlurFactor - 0.3) / 0.7);
            float distanceFromCenter = length(p);
            float gaussianAlpha = exp(-distanceFromCenter * distanceFromCenter / (gaussianRadius * gaussianRadius)) * uOpacity;

            float sdfAlpha = (1.0 - smoothstep(-0.2, 0.1, dist)) * uOpacity;

            float blendFactor = smoothstep(0.3, 0.8, uBlurFactor);
            alpha = mix(sdfAlpha, gaussianAlpha, blendFactor);
        }

        vec2 grainUv = vPosition * (2.0 + uBlurFactor * 3.0);
        float grain = random(grainUv + vec2(fract(uBlurFactor * 123.456)));
        float grainStrength = mix(0.05, 0.2, blurIntensity) * alpha;

        // Dark mode: use blue color directly for normal alpha blending
        vec3 baseColor = uColor.rgb * 0.7;
        float outputAlpha = alpha;

        float grainEffect = mix(1.0, grain, grainStrength);
        vec3 finalColor = baseColor * grainEffect;

        gl_FragColor = vec4(finalColor, outputAlpha);
    }
`;