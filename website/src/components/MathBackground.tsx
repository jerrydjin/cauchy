"use client";

import { useEffect, useRef } from "react";

const VERTEX_SHADER = `
  attribute vec2 position;
  void main() {
    gl_Position = vec4(position, 0.0, 1.0);
  }
`;

const FRAGMENT_SHADER = `
  #extension GL_OES_standard_derivatives : enable
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

    // Flowing horizontal ribbon
    float wave = 0.0;
    
    // Generate multiple overlapping sine waves
    for (float i = 1.0; i <= 5.0; i++) {
        float f = pos.x * (1.2 + i * 0.3) - u_time * (0.5 + i * 0.15);
        wave += sin(f) * (0.15 / i);
    }
    
    // Mouse interference pushing the strings
    float mouseDist = length(pos - mouse);
    // Smooth out mouse interference
    float interference = exp(-mouseDist * 4.0) * 0.2 * sin(mouseDist * 10.0 - u_time * 2.0);
    wave += interference;

    // Render dense horizontal lines along the wave
    float density = 15.0; // Ribbon density
    float yScaled = (pos.y - wave) * density;
    
    // Anti-aliased lines using fwidth
    float dz = fwidth(yScaled);
    float distToLine = abs(fract(yScaled) - 0.5);
    float pixelDist = distToLine / max(dz, 0.00001);
    
    // Half-thickness in pixels
    float halfThickness = 0.6; 
    float lineIntensity = 1.0 - smoothstep(halfThickness - 0.3, halfThickness + 0.3, pixelDist);

    // Fade out towards the edges
    float fade = 1.0;
    
    // Fade based on distance from center of ribbon
    fade *= exp(-abs(pos.y - wave) * 1.5);
    
    // Smooth fade out towards the bottom of the container
    fade *= smoothstep(-1.0, -0.1, pos.y);

    vec3 lineColor = vec3(23.0 / 255.0, 23.0 / 255.0, 23.0 / 255.0);
    
    gl_FragColor = vec4(lineColor, lineIntensity * fade * 0.5);
  }
`;

export default function MathBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const gl = canvas.getContext("webgl", { alpha: true });
    if (!gl) return;

    const ext = gl.getExtension("OES_standard_derivatives");
    if (!ext) {
      console.warn("OES_standard_derivatives not supported");
    }

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
      const rect = canvas.getBoundingClientRect();
      const displayWidth = rect.width;
      const displayHeight = rect.height;
      
      canvas.width = displayWidth * dpr;
      canvas.height = displayHeight * dpr;
      
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
      const rect = canvas.getBoundingClientRect();
      targetMouseX = (e.clientX - rect.left) * dpr;
      // Invert Y for WebGL
      targetMouseY = (rect.height - (e.clientY - rect.top)) * dpr;
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
