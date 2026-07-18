"use client";

import { useEffect, useRef } from "react";

const VERTEX_SHADER = `
  attribute vec2 position;
  void main() {
    gl_Position = vec4(position, 0.0, 1.0);
  }
`;

const FRAGMENT_SHADER = `
  precision highp float;

  uniform vec2 u_resolution;
  uniform float u_time;
  uniform vec2 u_mouse;

  void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 pos = uv * 2.0 - 1.0;
    pos.x *= u_resolution.x / u_resolution.y;

    // Mouse coordinates
    vec2 mouse = u_mouse / u_resolution.xy;
    mouse = mouse * 2.0 - 1.0;
    mouse.x *= u_resolution.x / u_resolution.y;

    // Cauchy-esque mathematical surface
    // z = f(x, y, t)
    float r = length(pos);
    float theta = atan(pos.y, pos.x);
    
    // Base topology
    float z = sin(pos.x * 3.0 + u_time * 0.1) * cos(pos.y * 3.0 + u_time * 0.15) * 3.0;
    z += sin(r * 8.0 - u_time * 0.3);
    
    // Mouse interference (creates a local topological distortion)
    float mouseDist = length(pos - mouse);
    float interference = exp(-mouseDist * 3.0) * 2.0 * cos(mouseDist * 15.0 - u_time * 3.0);
    z += interference;

    // Isolate contour lines using fract
    float contour = abs(fract(z) - 0.5);
    
    // Smooth lines
    float lineThickness = 0.05;
    float lineIntensity = smoothstep(lineThickness + 0.03, lineThickness, contour);

    // Fade out towards the edges
    float fade = smoothstep(2.0, 0.1, r);

    // Warm coffee accent color: #E6D5B8 -> rgb(230, 213, 184)
    // Darkened to be visible on white background: #D4C1A0 -> rgb(212, 193, 160)
    // Let's make it primary color #1C1917 -> rgb(28, 25, 23) for stronger contrast
    vec3 lineColor = vec3(28.0 / 255.0, 25.0 / 255.0, 23.0 / 255.0);
    
    // Render lines with transparency
    gl_FragColor = vec4(lineColor, lineIntensity * fade * 0.4);
  }
`;

export default function MathBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const gl = canvas.getContext("webgl", { alpha: true });
    if (!gl) return;

    // Create shaders
    const vertexShader = gl.createShader(gl.VERTEX_SHADER)!;
    gl.shaderSource(vertexShader, VERTEX_SHADER);
    gl.compileShader(vertexShader);

    const fragmentShader = gl.createShader(gl.FRAGMENT_SHADER)!;
    gl.shaderSource(fragmentShader, FRAGMENT_SHADER);
    gl.compileShader(fragmentShader);

    // Create program
    const program = gl.createProgram()!;
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);
    gl.useProgram(program);

    // Set up geometry (full screen quad)
    const vertices = new Float32Array([
      -1, -1,
       1, -1,
      -1,  1,
      -1,  1,
       1, -1,
       1,  1,
    ]);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

    const positionLoc = gl.getAttribLocation(program, "position");
    gl.enableVertexAttribArray(positionLoc);
    gl.vertexAttribPointer(positionLoc, 2, gl.FLOAT, false, 0, 0);

    // Uniforms
    const resLoc = gl.getUniformLocation(program, "u_resolution");
    const timeLoc = gl.getUniformLocation(program, "u_time");
    const mouseLoc = gl.getUniformLocation(program, "u_mouse");

    let animationFrameId: number;
    let mouseX = 0;
    let mouseY = 0;
    let targetMouseX = 0;
    let targetMouseY = 0;
    
    const startTime = Date.now();

    const resize = () => {
      const dpr = window.devicePixelRatio || 1;
      canvas.width = window.innerWidth * dpr;
      canvas.height = window.innerHeight * dpr;
      canvas.style.width = `${window.innerWidth}px`;
      canvas.style.height = `${window.innerHeight}px`;
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(resLoc, canvas.width, canvas.height);
      
      // Init mouse to center
      if (targetMouseX === 0 && targetMouseY === 0) {
        targetMouseX = canvas.width / 2;
        targetMouseY = canvas.height / 2;
        mouseX = targetMouseX;
        mouseY = targetMouseY;
      }
    };

    const onMouseMove = (e: MouseEvent) => {
      const dpr = window.devicePixelRatio || 1;
      targetMouseX = e.clientX * dpr;
      // Invert Y for WebGL
      targetMouseY = (window.innerHeight - e.clientY) * dpr;
    };

    window.addEventListener("resize", resize);
    window.addEventListener("mousemove", onMouseMove);
    resize();

    const render = () => {
      // Smooth mouse interpolation
      mouseX += (targetMouseX - mouseX) * 0.05;
      mouseY += (targetMouseY - mouseY) * 0.05;

      const time = (Date.now() - startTime) / 1000;
      
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      
      gl.uniform1f(timeLoc, time);
      gl.uniform2f(mouseLoc, mouseX, mouseY);
      
      // Enable blending
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      
      animationFrameId = requestAnimationFrame(render);
    };
    render();

    return () => {
      window.removeEventListener("resize", resize);
      window.removeEventListener("mousemove", onMouseMove);
      cancelAnimationFrame(animationFrameId);
      gl.deleteProgram(program);
      gl.deleteShader(vertexShader);
      gl.deleteShader(fragmentShader);
      gl.deleteBuffer(buffer);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="absolute inset-0 w-full h-full"
      style={{ pointerEvents: "none" }}
    />
  );
}
