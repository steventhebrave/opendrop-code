import processing.serial.*;
import static javax.swing.JOptionPane.*;

Serial myPort;

// Grid dimensions
final int GRID_WIDTH = 14;
final int GRID_HEIGHT = 8;
final int NUM_CARS = 4; // Number of cars in the conveyor belt

// Game state
boolean[][] electrodes = new boolean[GRID_WIDTH][GRID_HEIGHT];
boolean gameOver = false;
boolean paused = false; // Game paused flag

// Car (drop) management
class Car {
    int x;
    int y;
    int direction; // 0: right, 1: down, 2: left, 3: up
    
    Car(int startX, int startY, int dir) {
        x = startX;
        y = startY;
        direction = dir;
    }
    
    void move() {
        switch(direction) {
            case 0: // moving right
                x++;
                if (x >= GRID_WIDTH - 1) {
                    x = GRID_WIDTH - 1;
                    direction = 1; // start moving down
                }
                break;
            case 1: // moving down
                y++;
                if (y >= 4) { // Changed to middle row (4)
                    y = 4;
                    direction = 2; // start moving left
                }
                break;
            case 2: // moving left
                x--;
                if (x <= 0) {
                    x = 0;
                    direction = 3; // start moving up
                }
                break;
            case 3: // moving up
                y--;
                if (y <= 2) { // Changed to middle row (2)
                    y = 2;
                    direction = 0; // start moving right
                }
                break;
        }
    }
}

ArrayList<Car> cars = new ArrayList<Car>();
PVector frog;

// Timing
long lastMoveTime = 0;
int moveInterval = 400; // Milliseconds between car moves

void setup() {
    noLoop(); // Stop the draw() loop during setup
    
    // Serial port initialization
    String[] portList = Serial.list();
    if (portList == null || portList.length == 0) {
        println("FATAL ERROR: No serial ports found.");
        showMessageDialog(null, "No serial (COM) ports found.\nPlease ensure your OpenDrop device is connected and check your drivers.", "Serial Port Error", ERROR_MESSAGE);
        exit();
        return;
    }
    
    println("Available serial ports:");
    printArray(portList);
    
    String portName = portList[0];
    println("Connecting to: " + portName);
    myPort = new Serial(this, portName, 115200);
    delay(100);
    
    // Initialize game
    setupGame();
    frameRate(60);
    lastMoveTime = millis();
    
    loop(); // Restart the draw() loop
}

void setupGame() {
    // Clear the board
    for (int r = 0; r < GRID_HEIGHT; r++) {
        for (int c = 0; c < GRID_WIDTH; c++) {
            electrodes[c][r] = false;
        }
    }
    
    // Calculate total perimeter length for 3-row belt
    int perimeter = 2 * (GRID_WIDTH + 2); // 2 * (width + height-2) where height is 3
    int spacing = perimeter / NUM_CARS; // Space between cars
    
    // Initialize cars evenly distributed around the perimeter
    for (int i = 0; i < NUM_CARS; i++) {
        int position = (i * spacing) % perimeter;
        int x, y, dir;
        
        if (position < GRID_WIDTH - 1) {
            // Top edge of belt
            x = position;
            y = 2; // Middle row start
            dir = 0; // moving right
        } else if (position < GRID_WIDTH + 2) {
            // Right edge
            x = GRID_WIDTH - 1;
            y = 2 + (position - (GRID_WIDTH - 1)); // Start from middle row
            dir = 1; // moving down
        } else if (position < 2 * GRID_WIDTH + 1) {
            // Bottom edge of belt
            x = (2 * GRID_WIDTH + 1) - position;
            y = 4; // Middle row end
            dir = 2; // moving left
        } else {
            // Left edge
            x = 0;
            y = 4 - (perimeter - position); // Start from bottom of belt
            dir = 3; // moving up
        }
        
        cars.add(new Car(x, y, dir));
    }
    
    // Initialize frog at bottom middle (below the conveyor belt)
    frog = new PVector(GRID_WIDTH / 2, GRID_HEIGHT - 1);
    
    // Initial board state
    drawBoard();
    transmit();
}

void draw() {
    if (!gameOver && !paused) {
        // Move cars at regular intervals
        if (millis() - lastMoveTime > moveInterval) {
            updateGame();
            lastMoveTime = millis();
        }
    }
    drawBoard();
    transmit();
}

void updateGame() {
    // Move all cars
    for (Car car : cars) {
        car.move();
    }
}

void drawBoard() {
    // Clear electrodes
    for (int x = 0; x < GRID_WIDTH; x++) {
        for (int y = 0; y < GRID_HEIGHT; y++) {
            electrodes[x][y] = false;
        }
    }
    
    // Draw cars
    for (Car car : cars) {
        if (car.x >= 0 && car.x < GRID_WIDTH && car.y >= 0 && car.y < GRID_HEIGHT) {
            electrodes[car.x][car.y] = true;
        }
    }
    
    // Draw frog
    if (frog.x >= 0 && frog.x < GRID_WIDTH && frog.y >= 0 && frog.y < GRID_HEIGHT) {
        electrodes[int(frog.x)][int(frog.y)] = true;
    }
}

void transmit() {
    // Build and send the 32-byte packet
    byte[] packet = new byte[32];
    
    // Main grid columns
    for (int x = 0; x < GRID_WIDTH; x++) {
        int columnByte = 0;
        for (int y = 0; y < GRID_HEIGHT; y++) {
            if (electrodes[x][y]) {
                columnByte |= (1 << y);
            }
        }
        packet[x + 1] = (byte)columnByte;
    }
    
    // Send packet byte-by-byte
    for (int i = 0; i < packet.length; i++) {
        myPort.write(packet[i]);
    }
}

void keyPressed() {
    if (gameOver) {
        if (key == 'r' || key == 'R') {
            setupGame();
        }
        return;
    }
    
    // Toggle pause with 'p'
    if (key == 'p' || key == 'P') {
        paused = !paused;
        if (!paused) {
            lastMoveTime = millis(); // Prevent jump after pause
        }
        return; // Nothing else to do this frame
    }
    // If paused, ignore other key inputs except 'p'
    if (paused) {
        return;
    }
    
    // Move frog with arrow keys
    if (keyCode == UP && frog.y > 0) {
        frog.y--;
    } else if (keyCode == DOWN && frog.y < GRID_HEIGHT - 1) {
        frog.y++;
    } else if (keyCode == LEFT && frog.x > 0) {
        frog.x--;
    } else if (keyCode == RIGHT && frog.x < GRID_WIDTH - 1) {
        frog.x++;
    }
}

void dispose() {
    println("Sketch is closing. Clearing all electrodes.");
    if (myPort != null) {
        byte[] clearPacket = new byte[32];
        for (int i = 0; i < clearPacket.length; i++) {
            myPort.write(clearPacket[i]);
        }
        delay(50);
        myPort.stop();
    }
    super.dispose();
} 
