
import java.awt.AWTException;
import java.awt.MouseInfo;
import java.awt.Point;
import java.awt.Robot;
import com.jogamp.newt.opengl.GLWindow;

final int WORLD_SIZE = 32;
final float BLOCK = 48;
final float EYE_HEIGHT = 76;
final float PLAYER_HEIGHT = 86;
final float PLAYER_RADIUS = 13;
final float WALK_SPEED = 215;
final float RUN_SPEED = 330;
final float GRAVITY = 1050;
final float JUMP_SPEED = 430;

int[][] terrain = new int[WORLD_SIZE][WORLD_SIZE];
boolean[] held = new boolean[512];

PVector player = new PVector();       // x, feet y, z (Processing의 +y는 아래쪽)
float velocityY = 0;
float yaw = 0;
float pitch = 0;
boolean onGround = false;
boolean mouseLocked = true;
long previousMillis;
Robot robot;
GLWindow window;
int lastPointerX;
int lastPointerY;
boolean pointerSampleReady = false;

void setup() {
  size(1100, 700, P3D);
  pixelDensity(1);
  perspective(PI / 3.0, float(width) / height, 1, 5000);
  noiseSeed(240519);
  makeTerrain();

  player.x = WORLD_SIZE * BLOCK * 0.5;
  player.z = WORLD_SIZE * BLOCK * 0.5;
  player.y = groundY(player.x, player.z);
  previousMillis = millis();

  try {
    robot = new Robot();
    window = (GLWindow)surface.getNative();
  }
  catch (Exception e) {
    robot = null; // Robot을 사용할 수 없어도 드래그로 시점을 조절할 수 있다.
  }
  noCursor();
}

void draw() {
  long now = millis();
  float dt = constrain((now - previousMillis) / 1000.0, 0, 0.05);
  previousMillis = now;

  updateMouseLook();
  updatePlayer(dt);
  renderWorld();
  drawHUD();
}

void makeTerrain() {
  for (int x = 0; x < WORLD_SIZE; x++) {
    for (int z = 0; z < WORLD_SIZE; z++) {
      float n = noise(x * 0.105, z * 0.105);
      terrain[x][z] = 2 + int(n * 6);
    }
  }

  // 시작 지점 주변은 편하게 움직일 수 있도록 평탄하게 만든다.
  int c = WORLD_SIZE / 2;
  int spawnHeight = terrain[c][c];
  for (int x = c - 2; x <= c + 2; x++)
    for (int z = c - 2; z <= c + 2; z++)
      terrain[x][z] = spawnHeight;
}

void updateMouseLook() {
  if (!mouseLocked || !focused) {
    pointerSampleReady = false;
    return;
  }

  Point p = MouseInfo.getPointerInfo().getLocation();
  if (!pointerSampleReady) {
    // 잠금 직후나 커서 재배치 직후에는 현재 위치를 기준점으로만 사용한다.
    lastPointerX = p.x;
    lastPointerY = p.y;
    pointerSampleReady = true;
    return;
  }

  int dx = p.x - lastPointerX;
  int dy = p.y - lastPointerY;
  lastPointerX = p.x;
  lastPointerY = p.y;

  // 화면 좌표의 고정 오차가 아니라 실제 포인터 이동량만 시점에 반영한다.
  if (abs(dx) <= width / 2 && abs(dy) <= height / 2) {
    yaw += dx * 0.0026;
    pitch = constrain(pitch + dy * 0.0026, -HALF_PI + 0.02, HALF_PI - 0.02);
  }

}

void updatePlayer(float dt) {
  float forward = (isHeld('w') ? 1 : 0) - (isHeld('s') ? 1 : 0);
  float strafe  = (isHeld('d') ? 1 : 0) - (isHeld('a') ? 1 : 0);
  PVector motion = new PVector();

  if (forward != 0 || strafe != 0) {
    motion.set(sin(yaw) * forward + cos(yaw) * strafe,
               0,
               -cos(yaw) * forward + sin(yaw) * strafe);
    motion.normalize().mult((isHeld(CONTROL) ? RUN_SPEED : WALK_SPEED) * dt);
  }

  tryHorizontalMove(motion.x, 0);
  tryHorizontalMove(0, motion.z);

  velocityY += GRAVITY * dt;
  player.y += velocityY * dt;
  float floor = groundY(player.x, player.z);
  if (player.y >= floor) {
    player.y = floor;
    velocityY = 0;
    onGround = true;
  } else {
    onGround = false;
  }
}

void tryHorizontalMove(float dx, float dz) {
  if (dx == 0 && dz == 0) return;
  float nx = player.x + dx;
  float nz = player.z + dz;
  float margin = PLAYER_RADIUS + 1;
  nx = constrain(nx, margin, WORLD_SIZE * BLOCK - margin);
  nz = constrain(nz, margin, WORLD_SIZE * BLOCK - margin);

  // 몸통 둘레 네 점을 조사해 한 블록보다 높은 절벽은 통과하지 못하게 한다.
  // y가 작을수록 더 높은 지면이다.
  float highest = min(min(groundY(nx - PLAYER_RADIUS, nz - PLAYER_RADIUS),
                          groundY(nx + PLAYER_RADIUS, nz - PLAYER_RADIUS)),
                      min(groundY(nx - PLAYER_RADIUS, nz + PLAYER_RADIUS),
                          groundY(nx + PLAYER_RADIUS, nz + PLAYER_RADIUS)));
  float rise = player.y - highest;
  if (rise <= BLOCK * 0.62) {
    player.x = nx;
    player.z = nz;
    if (onGround && highest < player.y) player.y = highest;
  }
}

float groundY(float wx, float wz) {
  int gx = constrain(floor(wx / BLOCK), 0, WORLD_SIZE - 1);
  int gz = constrain(floor(wz / BLOCK), 0, WORLD_SIZE - 1);
  return -terrain[gx][gz] * BLOCK;
}

void renderWorld() {
  background(125, 190, 238);
  float eyeY = player.y - EYE_HEIGHT;
  PVector look = new PVector(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw));
  camera(player.x, eyeY, player.z,
         player.x + look.x, eyeY + look.y, player.z + look.z,
         0, 1, 0);

  ambientLight(115, 120, 125);
  directionalLight(245, 238, 215, -0.5, 0.85, -0.35);
  noStroke();

  for (int x = 0; x < WORLD_SIZE; x++) {
    for (int z = 0; z < WORLD_SIZE; z++) {
      int h = terrain[x][z];
      for (int y = 0; y < h; y++) {
        if (y == h - 1) fill(92, 166, 72);
        else if (y >= h - 3) fill(125, 91, 58);
        else fill(105, 108, 112);
        pushMatrix();
        translate((x + 0.5) * BLOCK, -(y + 0.5) * BLOCK, (z + 0.5) * BLOCK);
        box(BLOCK + 0.35);
        popMatrix();
      }
    }
  }

  // 월드 바닥 아래가 비어 보이지 않도록 기반암 판을 둔다.
  fill(67, 70, 75);
  pushMatrix();
  translate(WORLD_SIZE * BLOCK / 2, BLOCK / 2, WORLD_SIZE * BLOCK / 2);
  box(WORLD_SIZE * BLOCK, BLOCK, WORLD_SIZE * BLOCK);
  popMatrix();
}

void drawHUD() {
  hint(DISABLE_DEPTH_TEST);
  camera();
  ortho();
  noLights();

  stroke(255);
  strokeWeight(2);
  line(width / 2 - 8, height / 2, width / 2 + 8, height / 2);
  line(width / 2, height / 2 - 8, width / 2, height / 2 + 8);

  noStroke();
  fill(0, 145);
  rect(14, 14, 390, 58, 8);
  fill(255);
  textSize(15);
  text("WASD 이동  |  Ctrl 달리기  |  Space 점프", 28, 38);
  text(mouseLocked ? "마우스 시점  |  ESC 커서 해제" : "화면을 클릭해 마우스 시점 활성화", 28, 61);
  hint(ENABLE_DEPTH_TEST);
}

boolean isHeld(int k) {
  return k >= 0 && k < held.length && held[k];
}

void keyPressed() {
  if (key == ESC) {
    key = 0; // Processing의 기본 종료 동작을 막는다.
    mouseLocked = false;
    cursor();
    return;
  }
  int k = key == CODED ? keyCode : Character.toLowerCase(key);
  if (k >= 0 && k < held.length) held[k] = true;
  if (key == ' ' && onGround) {
    velocityY = -JUMP_SPEED;
    onGround = false;
  }
}

void keyReleased() {
  int k = key == CODED ? keyCode : Character.toLowerCase(key);
  if (k >= 0 && k < held.length) held[k] = false;
}

void mousePressed() {
  mouseLocked = true;
  pointerSampleReady = false;
  noCursor();
}

void mouseDragged() {
  // Robot이 금지된 환경에서의 대체 조작.
  if (robot == null && mouseLocked) {
    yaw += (mouseX - pmouseX) * 0.006;
    pitch = constrain(pitch + (mouseY - pmouseY) * 0.006,
                      -HALF_PI + 0.02, HALF_PI - 0.02);
  }
}


