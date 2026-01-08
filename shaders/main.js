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
            alpha: true
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
            const delay = 500 + Math.random() * 1500; // 0.5-2 seconds
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
        // Black background
        this.gl.clearColor(0.0, 0.0, 0.0, 1.0);
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

            const color = [
                0.1 + Math.random() * 0.2,  // R: 0.1-0.3
                0.4 + Math.random() * 0.2,  // G: 0.4-0.6
                1.0,                        // B: 1.0 (full blue)
                1.0                         // A: 1.0
            ];

            const newSquare = new Square(this.gl, x, y, size, color, z);
            validPosition = true;

            // Check overlap with existing squares
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
            const color = [
                0.1 + Math.random() * 0.2,
                0.4 + Math.random() * 0.2,
                1.0,
                1.0
            ];
            this.squares.push(new Square(this.gl, x, y, size, color, z));
        }
    }
}

window.onload = () => {
    window.visualizer = new SquareVisualizer();
};