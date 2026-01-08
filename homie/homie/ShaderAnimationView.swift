//
//  ShaderAnimationView.swift
//  homie
//
//  Created by Maximilian Prokopp on 07.01.26.
//

import SwiftUI
import WebKit

/// A SwiftUI view that displays the WebGL shader animation
struct ShaderAnimationView: NSViewRepresentable {
    let size: CGFloat
    var color: Color = .blue  // Default blue, can be changed
    var spawnAreaSize: Double = 0.2  // Spawn area size (0.0 to 1.0, where 0.2 = 20% of canvas)
    var circleSize: Double = 0.8  // Circle crop size (0.0 to 1.0)
    var vignetteIntensity: Double = 0.5  // Vignette intensity (0.0 to 1.0)
    var isThinkingMode: Bool = false  // Whether in thinking mode (circular spawn pattern)
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        
        // Load the HTML with inline JavaScript
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload HTML when parameters change to update the animation
        // This ensures the spawn area, circle size, and vignette are updated dynamically
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
    
    // Inline HTML content with embedded JavaScript
    private var htmlContent: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    overflow: hidden;
                    background: transparent;
                }
                canvas {
                    width: 100%;
                    height: 100%;
                    display: block;
                }
            </style>
        </head>
        <body>
            <canvas id="glCanvas"></canvas>
            <script>
        \(shadersJS)
        
        \(mainJS)
            </script>
        </body>
        </html>
        """
    }
    
    // Inline shader source code
    private var shadersJS: String {
        """
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
            uniform float uGrainFactor;
            uniform float uCircleSize;
            uniform float uVignetteIntensity;
            uniform vec2 uCanvasSize;
            uniform sampler2D uOverlapTexture;
            uniform bool uOverlapPass;

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

                // Convert to normalized screen coordinates (centered at origin, range -1 to 1)
                vec2 screenCoord = gl_FragCoord.xy / uCanvasSize;
                vec2 centeredCoord = (screenCoord - 0.5) * 2.0;
                // Normalize by aspect ratio to get circular distance
                float aspectRatio = uCanvasSize.x / uCanvasSize.y;
                centeredCoord.x /= aspectRatio;
                float distanceFromCenter = length(centeredCoord);
                
                // Circular mask - crop everything outside the circle
                // uCircleSize is 0-1, map to actual radius (max radius is sqrt(2) for diagonal)
                float circleRadius = uCircleSize * 0.707; // 0.707 ≈ 1/sqrt(2) for normalized circle
                float circleMask = smoothstep(circleRadius + 0.02, circleRadius - 0.02, distanceFromCenter);
                if (circleMask < 0.01) {
                    discard;
                }

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
                    float distanceFromCenterBox = length(p);
                    float gaussianAlpha = exp(-distanceFromCenterBox * distanceFromCenterBox / (gaussianRadius * gaussianRadius)) * uOpacity;

                    float sdfAlpha = (1.0 - smoothstep(-0.2, 0.1, dist)) * uOpacity;

                    float blendFactor = smoothstep(0.3, 0.8, uBlurFactor);
                    alpha = mix(sdfAlpha, gaussianAlpha, blendFactor);
                }

                vec2 grainUv = vPosition * (0.05 + uGrainFactor * 0.05);
                float grain = random(grainUv + vec2(fract(uGrainFactor * 123.456)));
                float grainStrength = mix(0.1, 1.0, uGrainFactor) * alpha;

                vec3 baseColor = uColor.rgb * 0.7;
                
                // Apply circular mask
                alpha *= circleMask;
                
                // Apply vignette effect (fade at edges with adjustable blur)
                float vignetteStart = circleRadius * 0.6;
                float vignetteFade = smoothstep(vignetteStart, circleRadius, distanceFromCenter);
                float vignetteAlpha = 1.0 - vignetteFade * uVignetteIntensity;
                alpha *= vignetteAlpha;

                float outputAlpha = alpha;

                float grainEffect = mix(1.0, grain, grainStrength);
                vec3 finalColor = baseColor * grainEffect;
                
                // In overlap pass, output alpha in red channel for counting
                if (uOverlapPass) {
                    gl_FragColor = vec4(outputAlpha, 0.0, 0.0, 0.0);
                } else {
                    // Darken on overlap (main pass)
                    vec2 overlapCoord = gl_FragCoord.xy / uCanvasSize;
                    float overlapCount = texture2D(uOverlapTexture, overlapCoord).r;
                    // Darken based on overlap: 1 square = no darkening, 2+ squares = darken
                    // overlapCount represents number of overlapping squares
                    // Scale: 1.0 = 1 square, 2.0 = 2 squares, etc.
                    float darkenFactor = 1.0 - clamp((overlapCount - 1.0) * 0.3, 0.0, 0.7);
                    finalColor *= darkenFactor;
                    gl_FragColor = vec4(finalColor, outputAlpha);
                }
            }
        `;
        """
    }
    
    // Inline main JavaScript
    private var mainJS: String {
        """
        class Square {
            constructor(gl, x, y, size, color, z = 0, isThinkingMode = false) {
                this.gl = gl;
                // Store target position (where square should end up)
                this.targetX = x;
                this.targetY = y;
                // In thinking mode, start at spawn position; otherwise start at center
                if (isThinkingMode) {
                    this.x = x;
                    this.y = y;
                } else {
                    this.x = 0;
                    this.y = 0;
                }
                this.isThinkingMode = isThinkingMode;
                this.z = z;
                this.size = size;
                this.color = color;
                this.opacity = 1.0;
                this.blurFactor = 0.0;
                this.grainFactor = 0.1;
                this.creationTime = Date.now();
                this.lifetime = 1000;
                this.initialSize = 0.1;
                // Rotation: 45 degrees base + random -5 to +5 degrees
                const baseRotation = 45 * Math.PI / 180; // 45 degrees in radians
                const randomVariation = (Math.random() * 10 - 5) * Math.PI / 180; // ±5 degrees
                this.rotation = baseRotation + randomVariation;
            }

            overlapsWith(other) {
                // Use target positions for collision detection (where squares will end up)
                const thisLeft = this.targetX - this.size;
                const thisRight = this.targetX + this.size;
                const thisTop = this.targetY + this.size;
                const thisBottom = this.targetY - this.size;

                const otherLeft = other.targetX - other.size;
                const otherRight = other.targetX + other.size;
                const otherTop = other.targetY + other.size;
                const otherBottom = other.targetY - other.size;

                const overlapX = Math.max(0, Math.min(thisRight, otherRight) - Math.max(thisLeft, otherLeft));
                const overlapY = Math.max(0, Math.min(thisTop, otherTop) - Math.max(thisBottom, otherBottom));
                const overlapArea = overlapX * overlapY;

                const thisArea = (thisRight - thisLeft) * (thisTop - thisBottom);
                const otherArea = (otherRight - otherLeft) * (otherTop - otherBottom);

                return overlapArea / Math.min(thisArea, otherArea);
            }

            update() {
                const age = Date.now() - this.creationTime;
                const phase1Duration = 700; // 0-700ms: constant speed growth
                const phase2Duration = 300;   // 700-1000ms: easing growth + blur + fade
                
                if (age < phase1Duration) {
                    // Phase 1: Linear growth from 0.1 to 0.3 over 700ms
                    const phase1Progress = age / phase1Duration;
                    this.size = 0.1 + (0.3 - 0.1) * phase1Progress;
                    this.blurFactor = 0.0;
                    this.opacity = 1.0;
                    // Grain: transition from low (0.1) to semi-high (0.4) over 700ms
                    this.grainFactor = 0.1 + (0.4 - 0.1) * phase1Progress;
                    // In thinking mode, stay at spawn position; otherwise move from center to target
                    if (this.isThinkingMode) {
                        this.x = this.targetX;
                        this.y = this.targetY;
                    } else {
                        // Move from center (0, 0) to target position
                        this.x = this.targetX * phase1Progress;
                        this.y = this.targetY * phase1Progress;
                    }
                } else if (age < this.lifetime) {
                    // Phase 2: Easing growth from 0.3 to 0.4, blur 0 to 0.8, opacity 1.0 to 0.0 over 300ms
                    const phase2Age = age - phase1Duration;
                    const phase2Progress = phase2Age / phase2Duration;
                    
                    // Ease-out for size (decreasing speed): 1 - (1-t)^2
                    const easedProgress = 1 - Math.pow(1 - phase2Progress, 2);
                    this.size = 0.3 + (0.4 - 0.3) * easedProgress;
                    
                    // Linear blur increase from 0 to 0.8
                    this.blurFactor = 0.8 * phase2Progress;
                    
                    // Linear opacity fade from 1.0 to 0.0
                    this.opacity = 1.0 - phase2Progress;
                    
                    // Grain: become very high (0.8) over the last 300ms
                    this.grainFactor = 0.4 + (0.8 - 0.4) * phase2Progress;
                    
                    // Stay at target position during fade
                    this.x = this.targetX;
                    this.y = this.targetY;
                } else {
                    // Past lifetime
                    this.opacity = 0.0;
                }
                
                return this.opacity > 0;
            }
        }

        class SquareVisualizer {
            constructor() {
                this.canvas = document.querySelector('#glCanvas');
                this.gl = this.canvas.getContext('webgl', {
                    antialias: false,
                    alpha: true,
                    premultipliedAlpha: false
                });

                if (!this.gl) {
                    console.error('WebGL not supported');
                    return;
                }

                this.squares = [];
                this.focalDistance = -0.50;
                this.fNumber = 2.8;
                this.isThinkingMode = \(isThinkingMode);
                
                // Circular spawn center for thinking mode (counter-clockwise)
                this.spawnCenterAngle = 0; // Start at 0 degrees (right side)
                this.spawnCenterRadius = 0.3; // Radius of the circular path
                this.spawnCenterSpeed = 0.0015; // Angular speed (radians per frame, ~60fps = ~0.09 rad/sec = ~1 full rotation per ~70 seconds)
                this.lastFrameTime = Date.now();

                // Spawn sequence: [{count: number of spawns, delay: delay in ms}, ...]
                this.spawnSequence = [
                    {count: 2, delay: 1000},
                    {count: 1, delay: 1000},
                    {count: 1, delay: 100},
                    {count: 2, delay: 600},
                    {count: 1, delay: 300},
                    {count: 1, delay: 600},
                    {count: 1, delay: 600},
                    {count: 1, delay: 600},
                    {count: 1, delay: 1000},
                    {count: 3, delay: 300},
                    {count: 1, delay: 1000},
                    {count: 1, delay: 1500},
                    {count: 1, delay: 500},
                    {count: 2, delay: 1000},
                    {count: 1, delay: 1000},
                    {count: 1, delay: 100},
                    {count: 2, delay: 300},
                    {count: 1, delay: 300},
                    {count: 1, delay: 300}
                ];
                this.sequenceIndex = 0;

                this.initWebGL();
                this.initBuffers();
                this.setupEventListeners();

                // Start sequence-based spawning
                this.spawnInterval = null;
                this.startAutoSpawning();

                this.animate();
            }

            initWebGL() {
                const vertexShader = this.compileShader(this.gl.VERTEX_SHADER, vertexShaderSource);
                const fragmentShader = this.compileShader(this.gl.FRAGMENT_SHADER, fragmentShaderSource);

                this.program = this.gl.createProgram();
                this.gl.attachShader(this.program, vertexShader);
                this.gl.attachShader(this.program, fragmentShader);
                this.gl.linkProgram(this.program);

                if (!this.gl.getProgramParameter(this.program, this.gl.LINK_STATUS)) {
                    console.error('Shader program failed to link:', this.gl.getProgramInfoLog(this.program));
                    return;
                }

                this.locations = {
                    position: this.gl.getAttribLocation(this.program, 'aVertexPosition'),
                    modelView: this.gl.getUniformLocation(this.program, 'uModelViewMatrix'),
                    projection: this.gl.getUniformLocation(this.program, 'uProjectionMatrix'),
                    color: this.gl.getUniformLocation(this.program, 'uColor'),
                    opacity: this.gl.getUniformLocation(this.program, 'uOpacity'),
                    blurFactor: this.gl.getUniformLocation(this.program, 'uBlurFactor'),
                    grainFactor: this.gl.getUniformLocation(this.program, 'uGrainFactor'),
                    circleSize: this.gl.getUniformLocation(this.program, 'uCircleSize'),
                    vignetteIntensity: this.gl.getUniformLocation(this.program, 'uVignetteIntensity'),
                    canvasSize: this.gl.getUniformLocation(this.program, 'uCanvasSize'),
                    overlapTexture: this.gl.getUniformLocation(this.program, 'uOverlapTexture'),
                    overlapPass: this.gl.getUniformLocation(this.program, 'uOverlapPass'),
                };
                
                // Store parameters
                this.circleSize = \(circleSize);
                this.vignetteIntensity = \(vignetteIntensity);
                
                // Initialize framebuffer variables (will be created in setupEventListeners after canvas is sized)
                this.overlapFramebuffer = null;
                this.overlapTexture = null;
                
                // Expose update method for dynamic parameter changes
                this.updateParameters = (circleSize, vignetteIntensity) => {
                    this.circleSize = circleSize;
                    this.vignetteIntensity = vignetteIntensity;
                };
            }

            compileShader(type, source) {
                const shader = this.gl.createShader(type);
                this.gl.shaderSource(shader, source);
                this.gl.compileShader(shader);

                if (!this.gl.getShaderParameter(shader, this.gl.COMPILE_STATUS)) {
                    console.error('Shader compilation failed:', this.gl.getShaderInfoLog(shader));
                    this.gl.deleteShader(shader);
                    return null;
                }

                return shader;
            }

            initBuffers() {
                const positions = [
                    -10.0,  10.0,
                     10.0,  10.0,
                    -10.0, -10.0,
                     10.0, -10.0,
                ];

                const positionBuffer = this.gl.createBuffer();
                this.gl.bindBuffer(this.gl.ARRAY_BUFFER, positionBuffer);
                this.gl.bufferData(this.gl.ARRAY_BUFFER, new Float32Array(positions), this.gl.STATIC_DRAW);

                this.buffers = {
                    position: positionBuffer
                };
            }

            setupEventListeners() {
                window.addEventListener('resize', () => this.resizeCanvas());
                this.resizeCanvas();
                // Initialize overlap framebuffer after canvas is sized
                this.initOverlapFramebuffer();
            }

            startAutoSpawning() {
                const spawnNext = () => {
                    // Get current sequence step
                    const step = this.spawnSequence[this.sequenceIndex];
                    
                    // Spawn the specified number of squares (all at once)
                    for (let i = 0; i < step.count; i++) {
                        this.spawnRandomSquare();
                    }
                    
                    // Move to next step in sequence
                    this.sequenceIndex = (this.sequenceIndex + 1) % this.spawnSequence.length;
                    
                    // Schedule next spawn after the delay for this step
                    this.spawnInterval = setTimeout(spawnNext, step.delay);
                };
                spawnNext();
            }

            stopAutoSpawning() {
                if (this.spawnInterval) {
                    clearTimeout(this.spawnInterval);
                    this.spawnInterval = null;
                }
            }

            resizeCanvas() {
                this.canvas.width = window.innerWidth;
                this.canvas.height = window.innerHeight;
                this.gl.viewport(0, 0, window.innerWidth, window.innerHeight);
                // Recreate overlap framebuffer on resize
                this.initOverlapFramebuffer();
            }
            
            initOverlapFramebuffer() {
                // Delete existing framebuffer if it exists
                if (this.overlapFramebuffer) {
                    this.gl.deleteFramebuffer(this.overlapFramebuffer);
                }
                if (this.overlapTexture) {
                    this.gl.deleteTexture(this.overlapTexture);
                }
                
                // Create texture for overlap counting
                this.overlapTexture = this.gl.createTexture();
                this.gl.bindTexture(this.gl.TEXTURE_2D, this.overlapTexture);
                this.gl.texImage2D(
                    this.gl.TEXTURE_2D,
                    0,
                    this.gl.RGBA,
                    this.canvas.width,
                    this.canvas.height,
                    0,
                    this.gl.RGBA,
                    this.gl.UNSIGNED_BYTE,
                    null
                );
                this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
                this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
                this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
                this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
                
                // Create framebuffer
                this.overlapFramebuffer = this.gl.createFramebuffer();
                this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.overlapFramebuffer);
                this.gl.framebufferTexture2D(
                    this.gl.FRAMEBUFFER,
                    this.gl.COLOR_ATTACHMENT0,
                    this.gl.TEXTURE_2D,
                    this.overlapTexture,
                    0
                );
                
                // Unbind
                this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
                this.gl.bindTexture(this.gl.TEXTURE_2D, null);
            }

            calculateDepthOfFieldBlur(square) {
                const distanceFromFocus = Math.abs(square.z - this.focalDistance);
                const subjectDistance = 5.0;
                const aperture = 1.0 / this.fNumber;
                const circleOfConfusion = (distanceFromFocus * aperture) / subjectDistance;
                const maxBlur = 0.8;
                const blurFactor = Math.min(circleOfConfusion * 3.0, maxBlur);
                return blurFactor;
            }

            drawSquare(square, overlapPass = false) {
                const aspectRatio = this.canvas.width / this.canvas.height;
                const scaleFactor = Math.min(1.0, aspectRatio);
                
                const projectionMatrix = new Float32Array([
                    1.0 / aspectRatio, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    0, 0, 0, 1
                ]);

                const adjustedSize = square.size * scaleFactor;
                
                // Create rotation matrix
                const cosR = Math.cos(square.rotation);
                const sinR = Math.sin(square.rotation);
                
                // Model-view matrix with rotation: R * S * T
                // First scale, then rotate, then translate
                const modelViewMatrix = new Float32Array([
                    adjustedSize * cosR, adjustedSize * sinR, 0, 0,
                    -adjustedSize * sinR, adjustedSize * cosR, 0, 0,
                    0, 0, 1, 0,
                    square.x, square.y, 0, 1
                ]);

                this.gl.uniformMatrix4fv(this.locations.modelView, false, modelViewMatrix);
                this.gl.uniformMatrix4fv(this.locations.projection, false, projectionMatrix);
                this.gl.uniform4fv(this.locations.color, new Float32Array(square.color));
                this.gl.uniform1f(this.locations.opacity, square.opacity);
                this.gl.uniform1f(this.locations.blurFactor, square.blurFactor);
                this.gl.uniform1f(this.locations.grainFactor, square.grainFactor);

                this.gl.drawArrays(this.gl.TRIANGLE_STRIP, 0, 4);
            }

            animate() {
                // Update squares first
                this.squares = this.squares.filter(square => {
                    const isAlive = square.update();
                    return isAlive;
                });
                
                // Update circular spawn center in thinking mode (counter-clockwise)
                if (this.isThinkingMode) {
                    const currentTime = Date.now();
                    const deltaTime = currentTime - this.lastFrameTime;
                    this.lastFrameTime = currentTime;
                    // Move counter-clockwise: negative direction
                    // Speed: ~0.0015 rad/frame at 60fps = ~0.09 rad/sec = ~1 rotation per 70 seconds
                    this.spawnCenterAngle -= this.spawnCenterSpeed * (deltaTime / 16.67); // Normalize to 60fps
                    // Keep angle in range [0, 2π]
                    if (this.spawnCenterAngle < 0) {
                        this.spawnCenterAngle += 2 * Math.PI;
                    }
                } else {
                    this.lastFrameTime = Date.now();
                }

                // PASS 1: Count overlaps
                this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.overlapFramebuffer);
                this.gl.clearColor(0.0, 0.0, 0.0, 0.0);
                this.gl.clear(this.gl.COLOR_BUFFER_BIT);

                this.gl.useProgram(this.program);
                this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffers.position);
                this.gl.vertexAttribPointer(this.locations.position, 2, this.gl.FLOAT, false, 0, 0);
                this.gl.enableVertexAttribArray(this.locations.position);

                // Use additive blending to count overlaps
                this.gl.enable(this.gl.BLEND);
                this.gl.blendFunc(this.gl.ONE, this.gl.ONE);
                this.gl.blendEquation(this.gl.FUNC_ADD);

                // Set uniforms for overlap pass
                this.gl.uniform1f(this.locations.circleSize, this.circleSize);
                this.gl.uniform1f(this.locations.vignetteIntensity, this.vignetteIntensity);
                this.gl.uniform2f(this.locations.canvasSize, this.canvas.width, this.canvas.height);
                this.gl.uniform1i(this.locations.overlapTexture, 0);
                this.gl.uniform1i(this.locations.overlapPass, 1);

                // Draw all squares to count overlaps (just alpha, stored in red channel)
                for (const square of this.squares) {
                    this.drawSquare(square, true);
                }

                // PASS 2: Render final result with darkening
                this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
                this.gl.clearColor(0.0, 0.0, 0.0, 0.0);
                this.gl.clear(this.gl.COLOR_BUFFER_BIT);

                // Bind overlap texture
                this.gl.activeTexture(this.gl.TEXTURE0);
                this.gl.bindTexture(this.gl.TEXTURE_2D, this.overlapTexture);

                // Use normal blending for final render
                this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
                this.gl.blendEquation(this.gl.FUNC_ADD);

                // Set uniforms for main pass
                this.gl.uniform1i(this.locations.overlapPass, 0);

                // Draw all squares with darkening
                for (const square of this.squares) {
                    this.drawSquare(square, false);
                }

                requestAnimationFrame(() => this.animate());
            }

            spawnRandomSquare() {
                const initialSize = 0.1;
                const spawnAreaSize = \(spawnAreaSize);
                let x, y, z;
                let validPosition = false;
                let attempts = 0;

                while (!validPosition && attempts < 30) {
                    if (this.isThinkingMode) {
                        // In thinking mode: spawn at circular center position with small random offset
                        const centerX = Math.cos(this.spawnCenterAngle) * this.spawnCenterRadius;
                        const centerY = Math.sin(this.spawnCenterAngle) * this.spawnCenterRadius;
                        // Add small random offset (10% of spawn area)
                        const offsetRange = spawnAreaSize * 0.1;
                        x = centerX + (Math.random() * 2 - 1) * offsetRange;
                        y = centerY + (Math.random() * 2 - 1) * offsetRange;
                    } else {
                        // Normal mode: spawn randomly in area
                        const maxX = spawnAreaSize;
                        const maxY = spawnAreaSize;
                        x = (Math.random() * 2 - 1) * maxX;
                        y = (Math.random() * 2 - 1) * maxY;
                    }
                    z = (Math.random() * 2 - 1) * 2.0;

                    const color = \(colorRGB);

                    const newSquare = new Square(this.gl, x, y, initialSize, color, z, this.isThinkingMode);
                    validPosition = true;

                    for (const existingSquare of this.squares) {
                        if (existingSquare.opacity < 0.8) continue;
                        const overlap = newSquare.overlapsWith(existingSquare);
                        if (overlap > 0.4) {
                            validPosition = false;
                            break;
                        }
                    }
                    attempts++;
                }

                if (validPosition) {
                    const color = \(colorRGB);
                    this.squares.push(new Square(this.gl, x, y, initialSize, color, z, this.isThinkingMode));
                }
            }
        }

        window.onload = () => {
            window.visualizer = new SquareVisualizer();
        };
        """
    }
    
    // Convert SwiftUI Color to RGB array for JavaScript
    private var colorRGB: String {
        #if canImport(AppKit)
        let nsColor = NSColor(color)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            return "[0.1, 0.4, 1.0, 1.0]"  // Default blue
        }
        let r = rgbColor.redComponent
        let g = rgbColor.greenComponent
        let b = rgbColor.blueComponent
        
        // Add slight random variation for visual interest
        return """
        [
            \(r) + Math.random() * 0.1,
            \(g) + Math.random() * 0.1,
            \(b),
            1.0
        ]
        """
        #else
        return "[0.1, 0.4, 1.0, 1.0]"  // Default blue
        #endif
    }
}

