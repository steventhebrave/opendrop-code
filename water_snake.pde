// Use thread() /  / speedup uP software / baud rate

import processing.serial.*;
import processing.net.*; 
import static javax.swing.JOptionPane.*;
import java.util.*;

Serial myPort;

int xsize = 16;
int ysize = 8;
int send_value = 0;
int timeout=0;
boolean changed=true;

boolean[][] electrodes = new boolean[14][8]; // [x][y], x=0..13, y=0..7

// --- Snake Game Variables ---
final int GRID_WIDTH = 14;
final int GRID_HEIGHT = 8;
ArrayList<PVector> snake;
PVector food;
int direction; // 0: UP, 1: RIGHT, 2: DOWN, 3: LEFT
int currentScore = 0; // Optional: for displaying score later
boolean gameOver;
boolean foodOnRightSide = true; // Start by placing food on the right side.
boolean isPaused = false; // For pausing the game after food placement

// Snake movement deltas
int[] dx = {0, 1, 0, -1}; // For UP, RIGHT, DOWN, LEFT
int[] dy = {-1, 0, 1, 0}; // For UP, RIGHT, DOWN, LEFT

// Special Electrode States and Reservoir Definitions
byte specialElectrodesLeft = 0;  // State of 8 electrodes in column 0
byte specialElectrodesRight = 0; // State of 8 electrodes in column 15

final int RESERVOIR_TL = 0; // Top-Left
final int RESERVOIR_BL = 1; // Bottom-Left
final int RESERVOIR_TR = 2; // Top-Right
final int RESERVOIR_BR = 3; // Bottom-Right

final int sequenceFrameDelay = 300; // Milliseconds delay between sequence frames (slowed for debug)

// Sequence of 4-bit nibbles for dispensing. This is now used for all reservoirs.
final byte[] dispenseSequence = {
  0b1000, // Electrode 0
  0b1100, // Electrode 0 and 1
  0b0111, // Electrode 1, 2 and 3
  0b0001, // Electrode 3 (Drop frame target)
  0b1100, // Electrode 0 and 1
  0b1000, // Electrode 0
  0b0000  // All off
};
final int dispenseDropFrame = 3; // 0-indexed frame where drop moves to main grid.

// Timing for game updates
long lastMoveTime = 0;
int moveInterval = 300; // Milliseconds between snake moves. Lower is faster.
int foodMoveDelay = 100; // Milliseconds between food animation steps. Lower is faster.
int dispenseClearDelay = 50;  // ms delay after clearing the reservoir before starting.
int dispenseEndDelay = 100;   // ms delay after the sequence is fully complete.

void setup() {
  noLoop(); // IMPORTANT: Stop the draw() loop from running during setup

  // --- Serial Port Initialization with Error Handling ---
  String[] portList = Serial.list();
  if (portList == null || portList.length == 0) {
    println("FATAL ERROR: No serial ports found.");
    println("Please ensure your OpenDrop device is connected and drivers are installed.");
    // Display a pop-up message as well for better visibility
    showMessageDialog(null, "No serial (COM) ports found.\nPlease ensure your OpenDrop device is connected and check your drivers.", "Serial Port Error", ERROR_MESSAGE);
    exit(); // Stop the sketch
    return; // End setup
  }

  // List all the available serial ports
  println("Available serial ports:");
  printArray(portList);
  
  // Pick the correct port from the list (e.g., the first one)
  String portName = portList[0]; // Change the index if needed
  println("Connecting to: " + portName);
  myPort = new Serial(this, portName, 115200); // Use your baud rate
  delay(100); // Short delay to let serial port stabilize before sending data

  setupGame();
  frameRate(60); // Keep a high frame rate for responsive input
  lastMoveTime = millis(); // Initialize lastMoveTime
  
  loop(); // IMPORTANT: Restart the draw() loop now that setup is complete
}

void setupGame() {
  // snake = new ArrayList<PVector>();
  // snake.add(new PVector(GRID_WIDTH / 2, GRID_HEIGHT / 2)); // Start in the middle - will be replaced by dispense
  direction = 1; // Start moving right (can be adjusted after drop)
  gameOver = false;
  currentScore = 0;
  foodOnRightSide = true; // Reset for a new game

  println("Setting up game, attempting to dispense initial drops...");

  // --- Dispense initial drop for Snake (e.g., from Top-Left) ---
  // Clear the board before dispensing snake, so it's the only thing appearing from this sequence
  for (int r = 0; r < GRID_HEIGHT; r++) {
    for (int c = 0; c < GRID_WIDTH; c++) {
      electrodes[c][r] = false;
    }
  }
  specialElectrodesLeft = 0; // Also clear special electrodes before a clean dispense
  specialElectrodesRight = 0;
  transmit(); // Send cleared state
  delay(50); // Short delay

  // Dispense snake from Top-Left reservoir
  dispenseSequenceAndPlaceDrop(RESERVOIR_TL); 
  snake = new ArrayList<PVector>();
  snake.add(getDispenseLocation(RESERVOIR_TL)); // Snake starts where TL reservoir places its drop
  println("Snake drop dispensed at (" + snake.get(0).x + "," + snake.get(0).y + ")");

  // Dispense and move food to its first random location
  spawnFood(); 

  // Ensure the game board reflects the initial snake and food state before first game tick
  drawBoard();
  transmit();
}

void spawnFood() {
  // Pause game logic while this animation runs
  noLoop(); 
  
  // 1. Pick a single random target on the designated side, avoiding the snake's buffer zone.
  PVector target;
  do {
    int x, y;
    y = int(random(GRID_HEIGHT));
    if (foodOnRightSide) {
      x = int(random(GRID_WIDTH / 2, GRID_WIDTH));
    } else {
      x = int(random(GRID_WIDTH / 2));
    }
    target = new PVector(x, y);
  } while (isLocationTooCloseToSnake(target, snake));
  println("New food target: (" + target.x + "," + target.y + ")");

  // 2. Attempt to find a path to the chosen target. Do not re-pick the target.
  ArrayList<PVector> pathToFood = null;
  int startReservoir = -1;
  for (int res : getPrioritizedReservoirs(target)) {
    PVector startPos = getDispenseLocation(res);
    pathToFood = findPath(startPos, target, snake);
    if (pathToFood != null) {
      startReservoir = res;
      break; // Found a valid path
    }
  }

  // 3. Dispense with animation if a path was found, otherwise place instantly as a fallback.
  if (pathToFood != null) {
    println("Path found. Dispensing from reservoir " + startReservoir + "...");
    dispenseSequenceAndPlaceDrop(startReservoir, true, pathToFood);
  } else {
    println("WARNING: No path found to target. Placing food instantly.");
    food = target.copy();
  }

  println("Food placement complete.");
  foodOnRightSide = !foodOnRightSide; // Toggle for the next spawn

  // Pause the game until the player makes a move
  isPaused = true;
  println("Game is paused. Press an arrow key to continue.");
  loop(); 
}

// --- Droplet/Food Movement Logic ---

// Helper to get the grid coordinates for a reservoir's drop position.
PVector getDispenseLocation(int reservoirId) {
    if (reservoirId == RESERVOIR_TR) {
        return new PVector(13, 1);
    } else if (reservoirId == RESERVOIR_BR) {
        return new PVector(13, 6);
    } else if (reservoirId == RESERVOIR_TL) {
        return new PVector(0, 1);
    } else if (reservoirId == RESERVOIR_BL) {
        return new PVector(0, 6);
    }
    // This should never be reached with valid reservoir IDs.
    println("ERROR: Invalid reservoir ID in getDispenseLocation: " + reservoirId);
    return new PVector(-1, -1); 
}

// Returns a list of reservoirs to check, prioritized by which side the target is on.
ArrayList<Integer> getPrioritizedReservoirs(PVector target) {
  ArrayList<Integer> reservoirs = new ArrayList<>();
  boolean targetIsOnRight = target.x >= GRID_WIDTH / 2;

  if (targetIsOnRight) {
    // Prioritize right-side reservoirs
    reservoirs.add(RESERVOIR_TR);
    reservoirs.add(RESERVOIR_BR);
    reservoirs.add(RESERVOIR_TL);
    reservoirs.add(RESERVOIR_BL);
  } else {
    // Prioritize left-side reservoirs
    reservoirs.add(RESERVOIR_TL);
    reservoirs.add(RESERVOIR_BL);
    reservoirs.add(RESERVOIR_TR);
    reservoirs.add(RESERVOIR_BR);
  }
  return reservoirs;
}

// Helper to check if a location is on the snake or in any of the 8 surrounding squares.
boolean isLocationTooCloseToSnake(PVector loc, ArrayList<PVector> snake) {
  for (PVector segment : snake) {
    // Check if the location is within a 3x3 box around the snake segment
    if (abs(loc.x - segment.x) <= 1 && abs(loc.y - segment.y) <= 1) {
      return true;
    }
  }
  return false;
}

int TwoToOne(int x,int y){  // 2D array to 3D Translation
  return y+x*8;
}

void draw() {
  // Only update the game state if the game is not over and not paused
  if (!gameOver && !isPaused) {
    // Check if it's time to update the game state (move the snake)
    if (millis() - lastMoveTime > moveInterval) {
      updateGame();
      lastMoveTime = millis(); // Reset the timer for the next move
    }
  }
  drawBoard(); // Renamed from electrodes[0][0] = true; etc.
  transmit();  // Transmit Data
  // readJoystick(); // Check for joystick input after every transmission
}

void updateGame() {
  // 1. Get current head and compute next head position
  PVector head = snake.get(0).copy();
  head.x += dx[direction];
  head.y += dy[direction];

  // 2. Check for wall collisions
  if (head.x < 0 || head.x >= GRID_WIDTH || head.y < 0 || head.y >= GRID_HEIGHT) {
    gameOver = true;
    println("GAME OVER - Wall Collision");
    return;
  }

  // 3. Check for self-collisions (against the current body, excluding the head)
  for (int i = 1; i < snake.size(); i++) {
    PVector segment = snake.get(i);
    if (head.x == segment.x && head.y == segment.y) {
      gameOver = true;
      println("GAME OVER - Self Collision");
      return;
    }
  }

  // 4. Check if food is eaten BEFORE we modify the snake
  boolean ateFood = (head.x == food.x && head.y == food.y);

  // 5. Add the new head. The old food location is now officially part of the snake.
  snake.add(0, head);

  // 6. Handle the consequences of the move
  if (ateFood) {
    // Food was eaten: Increment score and spawn new food.
    // We DO NOT remove the tail, so the snake grows.
    currentScore++;
    spawnFood();
  } else {
    // Food was not eaten: This is a normal move, so remove the tail.
    snake.remove(snake.size() - 1);
  }
}

void drawBoard() {
  // Clear electrodes
  for (int x = 0; x < GRID_WIDTH; x++) {
    for (int y = 0; y < GRID_HEIGHT; y++) {
      electrodes[x][y] = false;
    }
  }

  // Draw snake
  for (PVector segment : snake) {
    if (segment.x >= 0 && segment.x < GRID_WIDTH && segment.y >= 0 && segment.y < GRID_HEIGHT) {
      electrodes[int(segment.x)][int(segment.y)] = true;
    }
  }

  // Draw food
   if (food.x >= 0 && food.x < GRID_WIDTH && food.y >= 0 && food.y < GRID_HEIGHT) {
    electrodes[int(food.x)][int(food.y)] = true;
   }
}

void keyPressed() {
  if (gameOver) {
    if (key == 'r' || key == 'R') { // Restart game
      setupGame();
    }
    return;
  }

  // If the game is paused, any arrow key press will unpause it.
  if (isPaused) {
    if (keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
      isPaused = false;
      lastMoveTime = millis(); // Reset timer to prevent instant move
      println("Game resumed.");
    }
  }

  // Standard direction change logic (only applies if not paused)
  if (keyCode == UP && direction != 2) { // Prevent 180 turn
    direction = 0;
  } else if (keyCode == RIGHT && direction != 3) {
    direction = 1;
  } else if (keyCode == DOWN && direction != 0) {
    direction = 2;
  } else if (keyCode == LEFT && direction != 1) {
    direction = 3;
  }
}

// void readJoystick() {
//     byte[] response = new byte[24];
//     int bytesRead = 0;
    
//     // Give the device a moment to respond.
//     delay(5); 
    
//     if (myPort.available() >= 24) {
//         bytesRead = myPort.readBytes(response);
//     }
    
//     if (bytesRead == 24) {
//         byte joystickState = response[17];
        
//         // If the game is paused, any joystick movement will unpause it.
//         if (isPaused && joystickState != 0) {
//             isPaused = false;
//             lastMoveTime = millis();
//             println("Game resumed by joystick.");
//         }

//         // Check the bits to determine direction
//         if ((joystickState & 0x01) != 0 && direction != 2) direction = 0; // UP
//         else if ((joystickState & 0x08) != 0 && direction != 3) direction = 1; // RIGHT
//         else if ((joystickState & 0x02) != 0 && direction != 0) direction = 2; // DOWN
//         else if ((joystickState & 0x04) != 0 && direction != 1) direction = 3; // LEFT
//     } else {
//         // Clear buffer if we didn't get a full packet, to prevent desync
//         while(myPort.available() > 0) myPort.read();
//     }
// }

// Helper function to reverse the bits of a 4-bit nibble.
// e.g., 0b1101 -> 0b1011
byte reverseNibble(byte n) {
  // We only operate on the 4 least significant bits.
  byte b = (byte) (n & 0x0F); 
  byte reversed_n = 0;
  for (int i = 0; i < 4; i++) {
    reversed_n <<= 1;
    reversed_n |= (b & 1);
    b >>= 1;
  }
  return reversed_n;
}

void transmit() {
    // We build a 32-byte packet and send it in one go.
    // Packet structure:
    // [0]      : Left special electrodes (col 0)
    // [1-14]   : Main 14x8 grid (cols 1-14)
    // [15]     : Right special electrodes (col 15)
    // [16-17]  : Dummy bytes for legacy hardware
    // [18-31]  : 14 control bytes (unused for now)
    byte[] packet = new byte[32];

    // 1. Left Special Electrodes (Column 0)
    packet[0] = specialElectrodesLeft;

    // 2. The 14 Main Grid Columns
    for (int x = 0; x < GRID_WIDTH; x++) { // GRID_WIDTH is 14
        int columnByte = 0;
        for (int y = 0; y < GRID_HEIGHT; y++) { // GRID_HEIGHT is 8
            if (electrodes[x][y]) {
                columnByte |= (1 << y);
            }
        }
        packet[x + 1] = (byte)columnByte;
    }

    // 3. Right Special Electrodes (Column 15)
    packet[15] = specialElectrodesRight;
    
    // Bytes 16-31 are for dummy/control and are already 0 from initialization.
    
    // Send packet byte-by-byte to avoid potential buffer issues with a single large write.
    for (int i = 0; i < packet.length; i++) {
      myPort.write(packet[i]);
    }
}

// Helper function to apply a 4-bit nibble to the correct special electrode byte
void updateReservoirState(int reservoirId, byte nibble) {
    // Note: nibble is treated as the 4 LSBs (e.g., 0b00001110)
    if (reservoirId == RESERVOIR_TL) { // Lower nibble of Left byte
        specialElectrodesLeft = (byte) ((specialElectrodesLeft & 0xF0) | (nibble & 0x0F));
    } else if (reservoirId == RESERVOIR_BL) { // Upper nibble of Left byte
        specialElectrodesLeft = (byte) ((specialElectrodesLeft & 0x0F) | (nibble << 4));
    } else if (reservoirId == RESERVOIR_TR) { // Lower nibble of Right byte
        specialElectrodesRight = (byte) ((specialElectrodesRight & 0xF0) | (nibble & 0x0F));
    } else if (reservoirId == RESERVOIR_BR) { // Upper nibble of Right byte
        specialElectrodesRight = (byte) ((specialElectrodesRight & 0x0F) | (nibble << 4));
    }
}

// Overload for simple dispensing (like the snake at the start) without movement.
void dispenseSequenceAndPlaceDrop(int reservoirId) {
  PVector dropLoc = getDispenseLocation(reservoirId);
  ArrayList<PVector> path = new ArrayList<>();
  path.add(dropLoc); // A simple path containing only the start/end point
  dispenseSequenceAndPlaceDrop(reservoirId, false, path);
}

// This function executes a pre-defined sequence of electrode activations to dispense a drop.
// It can optionally begin moving the droplet from the 'dispenseDropFrame' onwards.
void dispenseSequenceAndPlaceDrop(int reservoirId, boolean moveDuringSequence, ArrayList<PVector> path) {
    if (path == null || path.isEmpty()) {
      println("ERROR: Invalid path provided to dispenseSequence.");
      return;
    }
    PVector startPos = path.get(0);
    PVector endPos = path.get(path.size() - 1);

    // Determine target deposit location on main grid based on reservoir
    int targetX = (int)startPos.x;
    int targetY = (int)startPos.y;

    // Ensure target grid electrode is off before starting
    updateReservoirState(reservoirId, (byte) 0b0000);
    transmit();
    delay(dispenseClearDelay);

    // --- Part 1: Run the dispense sequence to hand the droplet off ---
    for (int i = 0; i < dispenseSequence.length; i++) {
        byte nibble = dispenseSequence[i];
        if (reservoirId == RESERVOIR_BL || reservoirId == RESERVOIR_BR) {
          nibble = reverseNibble(nibble);
        }
        updateReservoirState(reservoirId, nibble);

        // On the handoff frame, place the drop.
        if (i == dispenseDropFrame) {
            if (moveDuringSequence) {
                food = path.get(0).copy(); // Place food at start of path
                drawBoard(); // Show the food appearing for the first time
            } else {
                electrodes[targetX][targetY] = true; // Place the snake
            }
        }
        transmit();
        delay(sequenceFrameDelay); // Use the slow delay for the whole dispense sequence
    }

    // --- Part 2: If moving, animate the droplet along the rest of the path ---
    if (moveDuringSequence) {
        // Start from the second step of the path, since the first step was the handoff.
        for (int pathIndex = 1; pathIndex < path.size(); pathIndex++) {
            food = path.get(pathIndex).copy();
            drawBoard();
            transmit();
            delay(foodMoveDelay);
        }
    }

    // --- Part 3: Clean up reservoir and finalize ---
    updateReservoirState(reservoirId, (byte) 0b0000);
    transmit();
    delay(dispenseEndDelay);
    println("Dispense complete for reservoir " + reservoirId + ". Drop at (" + endPos.x + "," + endPos.y + ")");
}

void dispose() {
  println("Sketch is closing. Clearing all electrodes to prevent state-bleed on next run.");
  if (myPort != null) {
    // Send a 32-byte zero packet to clear the entire grid on the device
    byte[] clearPacket = new byte[32]; // Already initialized to zeros
    // Send byte-by-byte
    for (int i = 0; i < clearPacket.length; i++) {
      myPort.write(clearPacket[i]);
    }
    delay(50); // Give the port a moment to send before stopping
    myPort.stop(); // Properly close the port
  }
  super.dispose();
}

// Pathfinding function using Breadth-First Search (BFS)
// Returns a list of PVectors representing the path, or null if no path is found.
ArrayList<PVector> findPath(PVector start, PVector end, ArrayList<PVector> snake) {
    Queue<ArrayList<PVector>> queue = new LinkedList<>();
    boolean[][] visited = new boolean[GRID_WIDTH][GRID_HEIGHT];

    // Mark snake positions AND their neighbors as visited (as if they are walls)
    for (PVector segment : snake) {
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          int nx = (int)segment.x + dx;
          int ny = (int)segment.y + dy;
          if (nx >= 0 && nx < GRID_WIDTH && ny >= 0 && ny < GRID_HEIGHT) {
            visited[nx][ny] = true;
          }
        }
      }
    }

    // The starting point of the path
    ArrayList<PVector> startPath = new ArrayList<>();
    startPath.add(start);
    queue.add(startPath);
    
    // If the start position itself is blocked, no path is possible.
    // This can happen if the snake is right next to a reservoir exit.
    if (visited[(int)start.x][(int)start.y]) {
        return null; 
    }
    visited[(int)start.x][(int)start.y] = true;

    while (!queue.isEmpty()) {
        ArrayList<PVector> currentPath = queue.poll();
        PVector currentPos = currentPath.get(currentPath.size() - 1);

        if (currentPos.x == end.x && currentPos.y == end.y) {
            return currentPath; // Found the path
        }

        // Explore neighbors (UP, DOWN, LEFT, RIGHT)
        int[] dx = {0, 0, -1, 1};
        int[] dy = {-1, 1, 0, 0};

        for (int i = 0; i < 4; i++) {
            int newX = (int)currentPos.x + dx[i];
            int newY = (int)currentPos.y + dy[i];

            if (newX >= 0 && newX < GRID_WIDTH && newY >= 0 && newY < GRID_HEIGHT && !visited[newX][newY]) {
                visited[newX][newY] = true;
                ArrayList<PVector> newPath = new ArrayList<>(currentPath);
                newPath.add(new PVector(newX, newY));
                queue.add(newPath);
            }
        }
    }

    return null; // No path found
}
