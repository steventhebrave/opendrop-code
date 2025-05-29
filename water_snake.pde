// Use thread() /  / speedup uP software / baud rate

import processing.serial.*;
import processing.net.*; 
import static javax.swing.JOptionPane.*;

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

final int sequenceFrameDelay = 200; // Milliseconds delay between sequence frames

// Timing for game updates
long lastMoveTime = 0;
int moveInterval = 500; // Milliseconds between snake moves (e.g., 500ms for 2 moves/sec)

void setup() {
  // List all the available serial ports
  println(Serial.list());
  // Pick the correct port from the list (e.g., the first one)
  String portName = Serial.list()[0]; // Change the index if needed
  myPort = new Serial(this, portName, 115200); // Use your baud rate

  setupGame();
  frameRate(60); // Keep a high frame rate for responsive input
  lastMoveTime = millis(); // Initialize lastMoveTime

  //Initialize special electrodes to off
  specialElectrodesLeft = 0;
  specialElectrodesRight = 0;
  transmit(); // Send initial zero state for special electrodes
}

void setupGame() {
  // snake = new ArrayList<PVector>();
  // snake.add(new PVector(GRID_WIDTH / 2, GRID_HEIGHT / 2)); // Start in the middle - will be replaced by dispense
  direction = 1; // Start moving right (can be adjusted after drop)
  gameOver = false;
  currentScore = 0;

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

  dispenseSequenceAndPlaceDrop(RESERVOIR_TL); // This should place a drop at (0,1)
  snake = new ArrayList<PVector>();
  snake.add(new PVector(0, 1)); // Snake starts where TL reservoir places its drop
  println("Snake drop dispensed at (0,1)");

  // --- Dispense initial drop for Food (e.g., from Top-Right) ---
  // We need a sequence for TR first. For now, let's simulate its target and manually place food.
  // dispenseSequenceAndPlaceDrop(RESERVOIR_TR); // This would place a drop at (13,1)
  // food = new PVector(13,1); // Food starts where TR reservoir would place its drop
  // println("Food drop (simulated) at (13,1)");

  // For now, until TR dispense is also manual, use original random spawn for food AFTER snake is placed
  spawnFood(); 
  println("Food spawned randomly at (" + food.x + "," + food.y + ")");

  // Ensure the game board reflects the initial snake and food state before first game tick
  drawBoard();
  transmit();
}

void spawnFood() {
  food = new PVector(int(random(GRID_WIDTH)), int(random(GRID_HEIGHT)));
  // Ensure food doesn't spawn on the snake
  for (PVector segment : snake) {
    if (food.x == segment.x && food.y == segment.y) {
      spawnFood(); // Try again
      return;
    }
  }
}

int TwoToOne(int x,int y){  // 2D array to 3D Translation
  return y+x*8;
}

void draw() {
  if (!gameOver) {
    // Check if it's time to update the game state (move the snake)
    if (millis() - lastMoveTime > moveInterval) {
      updateGame();
      lastMoveTime = millis(); // Reset the timer for the next move
    }
  }
  drawBoard(); // Renamed from electrodes[0][0] = true; etc.
  transmit();  // Transmit Data
}

void updateGame() {
  // Move snake
  PVector head = snake.get(0).copy(); // Get current head
  head.x += dx[direction];
  head.y += dy[direction];

  // Check wall collisions
  if (head.x < 0 || head.x >= GRID_WIDTH || head.y < 0 || head.y >= GRID_HEIGHT) {
    gameOver = true;
    println("GAME OVER - Wall Collision");
    return;
  }

  // Check self collision
  for (int i = 1; i < snake.size(); i++) {
    PVector segment = snake.get(i);
    if (head.x == segment.x && head.y == segment.y) {
      gameOver = true;
      println("GAME OVER - Self Collision");
      return;
    }
  }

  // Check if food is eaten
  if (head.x == food.x && head.y == food.y) {
    currentScore++;
    // Snake grows, new head is added, tail is not removed
    spawnFood();
  } else {
    // Snake moves, remove tail
    if (snake.size() > 1 || (snake.size() == 1 && currentScore == 0)) { // only remove tail if snake has moved or is just starting
         if(snake.size() > 0) snake.remove(snake.size() - 1);
    } else if (snake.size() == 1 && currentScore > 0) {
        // if snake is just one segment long but has eaten, it means it just ate.
        // The old "tail" (which was the head before eating) should not be removed yet.
        // It will effectively grow on the next non-eating move.
    }


  }
   snake.add(0, head); // Add new head at the beginning of the list

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

void transmit() {
    String[] colBits = new String[16]; // For debug printing

    for (int x = 0; x < 16; x++) {
        int send_value = 0;
        if (x == 0) {
            send_value = specialElectrodesLeft;
        } else if (x == 15) {
            send_value = specialElectrodesRight;
        } else {
            // Main grid electrodes (columns 1 to 14 physical, mapping to electrodes[0] to electrodes[13])
            for (int y = 0; y < 8; y++) {
                send_value = send_value << 1;
                // electrodes array is 14 wide (0-13). Physical columns 1-14 map to these.
                // So, for physical column x (1-14), we use electrodes[x-1]
                send_value += electrodes[x - 1][7 - y] ? 1 : 0; 
            }
        }
        myPort.write(send_value); // Send the byte
        colBits[x] = String.format("%8s", Integer.toBinaryString(send_value & 0xFF)).replace(' ', '0');
    }

    // Print as 8x16 grid (rows y=0..7, representing MSB to LSB of each byte)
    // println("Electrode grid (Special | Main Grid | Special):");
    // for (int bitIndex = 7; bitIndex >= 0; bitIndex--) { // Print MSB (conceptual y=0) at the top
    //     String row = "";
    //     for (int col = 0; col < 16; col++) {
    //         row += colBits[col].charAt(7-bitIndex); // charAt(0) is MSB, charAt(7) is LSB
    //         if (col == 0 || col == 14) row += "|"; // Separators for special columns
    //         else row += " ";
    //     }
    //     println(row);
    // }
    // Simplified print for now, consistent with previous output where row 0 of printout is MSB of byte
    println("Electrode grid state sent (Col 0:LeftSpecial, Col 15:RightSpecial):");
    for (int y_print_row = 0; y_print_row < 8; y_print_row++) { // y_print_row 0 is MSB for each colBits string
        String rowString = "";
        for (int col_idx = 0; col_idx < 16; col_idx++) {
            rowString += colBits[col_idx].charAt(y_print_row);
            if (col_idx == 0 || col_idx == 14) rowString += "|";
            else rowString += " ";
        }
        println(rowString);
    }
    println("---"); 
}

// Helper function to set a specific electrode in a reservoir
// electrodeInReservoir: 0-3 (0 is typically the "highest" or first bit for that reservoir part)
void setReservoirElectrode(int reservoirId, int electrodeInReservoir, boolean on) {
    int bitToChange = 0; // This will be the bit position (0-7) within the byte

    if (reservoirId == RESERVOIR_TL) { // Uses bits 7,6,5,4 of specialElectrodesLeft
        // electrode 0 -> bit 7; electrode 1 -> bit 6; ... electrode 3 -> bit 4
        bitToChange = 7 - electrodeInReservoir;
        if (on) specialElectrodesLeft |= (1 << bitToChange);
        else specialElectrodesLeft &= ~(1 << bitToChange);
    } else if (reservoirId == RESERVOIR_BL) { // Uses bits 3,2,1,0 of specialElectrodesLeft
        // electrode 0 -> bit 3; electrode 1 -> bit 2; ... electrode 3 -> bit 0
        bitToChange = 3 - electrodeInReservoir;
        if (on) specialElectrodesLeft |= (1 << bitToChange);
        else specialElectrodesLeft &= ~(1 << bitToChange);
    } else if (reservoirId == RESERVOIR_TR) { // Uses bits 7,6,5,4 of specialElectrodesRight
        bitToChange = 7 - electrodeInReservoir;
        if (on) specialElectrodesRight |= (1 << bitToChange);
        else specialElectrodesRight &= ~(1 << bitToChange);
    } else if (reservoirId == RESERVOIR_BR) { // Uses bits 3,2,1,0 of specialElectrodesRight
        bitToChange = 3 - electrodeInReservoir;
        if (on) specialElectrodesRight |= (1 << bitToChange);
        else specialElectrodesRight &= ~(1 << bitToChange);
    }
}

// Placeholder for the actual drop dispensing logic
// This function will need the specific sequence of electrode activations and delays
void dispenseSequenceAndPlaceDrop(int reservoirId) {
    int targetX = 0, targetY = 0;
    println("Attempting to manually dispense from reservoir: " + reservoirId);

    // Determine target deposit location on main grid based on reservoir
    if (reservoirId == RESERVOIR_TL) { targetX = 0; targetY = 1; } // Target for Top-Left
    else if (reservoirId == RESERVOIR_BL) { targetX = 0; targetY = 6; }
    else if (reservoirId == RESERVOIR_TR) { targetX = 13; targetY = 1; }
    else if (reservoirId == RESERVOIR_BR) { targetX = 13; targetY = 6; }
    else { println("Invalid reservoir ID for dispensing: " + reservoirId); return; }

    if (reservoirId == RESERVOIR_TL) {
        println("Executing Top-Left Manual Dispense Sequence...");
        byte originalSpecialLeft = specialElectrodesLeft; // Store original state to only modify relevant bits
        // boolean originalTargetElectrodeState = electrodes[targetX][targetY]; // Store original state - Not needed if we are explicitly setting it

        // --- Frame 1 ---
        // y3.charAt(0) = '1' (Special Bit 4 ON)
        // y0,y1,y2.charAt(0) = '0'
        specialElectrodesLeft = (byte) ((originalSpecialLeft & 0x0F) | (1 << 4)); // Set bit 4, clear 7,6,5, keep lower 4 bits of original
        transmit(); delay(sequenceFrameDelay);
        println("Frame 1: Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0'));

        // --- Frame 2 ---
        // y2.charAt(0) = '1' (Special Bit 5 ON)
        // y3.charAt(0) = '1' (Special Bit 4 ON)
        // y0,y1.charAt(0) = '0'
        specialElectrodesLeft = (byte) ((originalSpecialLeft & 0x0F) | (1 << 5) | (1 << 4)); // Set bits 5,4, clear 7,6
        transmit(); delay(sequenceFrameDelay);
        println("Frame 2: Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0'));

        // --- Frame 3 ---
        // y0.charAt(0) = '1' (Special Bit 7 ON)
        // y1.charAt(0) = '1' (Special Bit 6 ON)
        // y2.charAt(0) = '1' (Special Bit 5 ON)
        // y3.charAt(0) = '0'
        specialElectrodesLeft = (byte) ((originalSpecialLeft & 0x0F) | (1 << 7) | (1 << 6) | (1 << 5)); // Set bits 7,6,5, clear 4
        transmit(); delay(sequenceFrameDelay);
        println("Frame 3: Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0'));

        // --- Frame 4 ---
        // y0.charAt(0) = '1' (Special Bit 7 ON)
        // y1,y2,y3.charAt(0) = '0'
        // Main grid electrodes[0][1] ON
        specialElectrodesLeft = (byte) ((originalSpecialLeft & 0x0F) | (1 << 7)); // Set bit 7, clear 6,5,4
        electrodes[targetX][targetY] = true; 
        transmit(); delay(sequenceFrameDelay);
        println("Frame 4: Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0') + " Target Grid ON");

        // --- Frame 5 ---
        // y2.charAt(0) = '1' (Special Bit 5 ON)
        // y3.charAt(0) = '1' (Special Bit 4 ON)
        // y0,y1.charAt(0) = '0'
        // Main grid electrodes[0][1] ON (remains ON)
        specialElectrodesLeft = (byte) ((originalSpecialLeft & 0x0F) | (1 << 5) | (1 << 4)); // Set bits 5,4, clear 7,6
        // electrodes[targetX][targetY] remains true
        transmit(); delay(sequenceFrameDelay);
        println("Frame 5: Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0') + " Target Grid ON");

        // --- Frame 6 ---
        // y3.charAt(0) = '1' (Special Bit 4 ON)
        // y0,y1,y2.charAt(0) = '0'
        // Main grid electrodes[0][1] ON (remains ON)
        specialElectrodesLeft = (byte) ((originalSpecialLeft & 0x0F) | (1 << 4)); // Set bit 4, clear 7,6,5
        // electrodes[targetX][targetY] remains true
        transmit(); delay(sequenceFrameDelay);
        println("Frame 6: Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0') + " Target Grid ON");
        
        // --- Final State ---
        // Turn off all 4 special electrodes for Top-Left, leave drop at targetX, targetY
        // Ensure only the top 4 bits of specialElectrodesLeft are affected for TL reservoir.
        // Lower 4 bits are preserved from whatever state they were in (e.g. for BL reservoir).
        specialElectrodesLeft &= 0x0F; // Clears bits 7,6,5,4 (TL reservoir), preserves bits 3,2,1,0 (BL reservoir)
        // electrodes[targetX][targetY] is already true from frame 6
        transmit();
        println("Top-Left Manual Dispense Sequence Finished. Left Special = " + String.format("%8s", Integer.toBinaryString(specialElectrodesLeft & 0xFF)).replace(' ', '0'));
        delay(100);

    } else {
        println("Dispense sequence for reservoir " + reservoirId + " not yet implemented. Simulating drop.");
        // Fallback for other reservoirs: Simulate drop appearing as before
        electrodes[targetX][targetY] = true;
        // Ensure special electrodes for THIS reservoir are off after simulated drop
        if (reservoirId == RESERVOIR_BL) {
            specialElectrodesLeft &= 0xF0; // Clear bottom 4 bits (BL)
        } else if (reservoirId == RESERVOIR_TR) {
            specialElectrodesRight &= 0x0F; // Clear top 4 bits (TR)
        } else if (reservoirId == RESERVOIR_BR) {
            specialElectrodesRight &= 0xF0; // Clear bottom 4 bits (BR)
        }
        transmit();
        delay(100);
    }
}
