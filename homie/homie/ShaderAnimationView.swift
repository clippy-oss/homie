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
        // Nothing to update
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

                vec3 baseColor = uColor.rgb * 0.7;
                float outputAlpha = alpha;

                float grainEffect = mix(1.0, grain, grainStrength);
                vec3 finalColor = baseColor * grainEffect;

                gl_FragColor = vec4(finalColor, outputAlpha);
            }
        `;
        """
    }
    
    // Inline main JavaScript
    private var mainJS: String {
        """
        class Square {
            constructor(gl, x, y, size, color, z = 0) {
                this.gl = gl;
                this.x = x;
                this.y = y;
                this.z = z;
                this.size = size;
                this.color = color;
                this.opacity = 1.0;
                this.blurFactor = 0.15;
                this.creationTime = Date.now();
                this.lifetime = 1500;
                this.initialSize = size;
            }

            overlapsWith(other) {
                const thisLeft = this.x - this.size;
                const thisRight = this.x + this.size;
                const thisTop = this.y + this.size;
                const thisBottom = this.y - this.size;

                const otherLeft = other.x - other.size;
                const otherRight = other.x + other.size;
                const otherTop = other.y + other.size;
                const otherBottom = other.y - this.size;

                const overlapX = Math.max(0, Math.min(thisRight, otherRight) - Math.max(thisLeft, otherLeft));
                const overlapY = Math.max(0, Math.min(thisTop, otherTop) - Math.max(thisBottom, otherBottom));
                const overlapArea = overlapX * overlapY;

                const thisArea = (thisRight - thisLeft) * (thisTop - thisBottom);
                const otherArea = (otherRight - otherLeft) * (otherTop - otherBottom);

                return overlapArea / Math.min(thisArea, otherArea);
            }

            update() {
                const age = Date.now() - this.creationTime;
                const progress = age / this.lifetime;
                this.opacity = Math.max(0, 1 - progress);
                this.size = this.initialSize * (1 - progress * 0.5);
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

                this.initWebGL();
                this.initBuffers();
                this.setupEventListeners();

                // Auto-spawn squares every 0.5-2 seconds
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
            }

            startAutoSpawning() {
                const spawnNext = () => {
                    this.spawnRandomSquare();
                    const delay = 250 + Math.random() * 750; // 0.25-1 second
                    this.spawnInterval = setTimeout(spawnNext, delay);
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

            drawSquare(square) {
                const dofBlur = this.calculateDepthOfFieldBlur(square);
                const aspectRatio = this.canvas.width / this.canvas.height;
                const scaleFactor = Math.min(1.0, aspectRatio);
                
                const projectionMatrix = new Float32Array([
                    1.0 / aspectRatio, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    0, 0, 0, 1
                ]);

                const adjustedSize = square.size * scaleFactor;
                
                const modelViewMatrix = new Float32Array([
                    adjustedSize, 0, 0, 0,
                    0, adjustedSize, 0, 0,
                    0, 0, 1, 0,
                    square.x, square.y, 0, 1
                ]);

                this.gl.uniformMatrix4fv(this.locations.modelView, false, modelViewMatrix);
                this.gl.uniformMatrix4fv(this.locations.projection, false, projectionMatrix);
                this.gl.uniform4fv(this.locations.color, new Float32Array(square.color));
                this.gl.uniform1f(this.locations.opacity, square.opacity);
                this.gl.uniform1f(this.locations.blurFactor, dofBlur);

                this.gl.drawArrays(this.gl.TRIANGLE_STRIP, 0, 4);
            }

            animate() {
                // Transparent background
                this.gl.clearColor(0.0, 0.0, 0.0, 0.0);
                this.gl.clear(this.gl.COLOR_BUFFER_BIT);

                this.gl.useProgram(this.program);

                this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffers.position);
                this.gl.vertexAttribPointer(this.locations.position, 2, this.gl.FLOAT, false, 0, 0);
                this.gl.enableVertexAttribArray(this.locations.position);

                this.gl.enable(this.gl.BLEND);
                this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);

                // Update and draw squares
                this.squares = this.squares.filter(square => {
                    const isAlive = square.update();
                    if (isAlive) {
                        this.drawSquare(square);
                    }
                    return isAlive;
                });

                requestAnimationFrame(() => this.animate());
            }

            spawnRandomSquare() {
                const size = 0.4;
                const maxX = 0.6 - size;
                const maxY = 0.6 - size;
                let x, y, z;
                let validPosition = false;
                let attempts = 0;

                while (!validPosition && attempts < 30) {
                    x = (Math.random() * 2 - 1) * maxX;
                    y = (Math.random() * 2 - 1) * maxY;
                    z = (Math.random() * 2 - 1) * 2.0;

                    const color = \(colorRGB);

                    const newSquare = new Square(this.gl, x, y, size, color, z);
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
                    this.squares.push(new Square(this.gl, x, y, size, color, z));
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

