// Update mapping in setReservoirElectrode for TL and BL
// ... existing code for helper function ...
void setReservoirElectrode(int reservoirId, int electrodeInReservoir, boolean on) {
    int bitToChange = 0; // bit position 0-7 within the byte

    if (reservoirId == RESERVOIR_TL) { // Uses bits 3,2,1,0 of specialElectrodesLeft
        bitToChange = 3 - electrodeInReservoir; // electrode 0 -> bit3, electrode3 -> bit0
        if (on) specialElectrodesLeft |= (1 << bitToChange);
        else specialElectrodesLeft &= ~(1 << bitToChange);
    } else if (reservoirId == RESERVOIR_BL) { // Uses bits 7,6,5,4 of specialElectrodesLeft
        bitToChange = 7 - electrodeInReservoir; // electrode0 -> bit7, electrode3 -> bit4
        if (on) specialElectrodesLeft |= (1 << bitToChange);
        else specialElectrodesLeft &= ~(1 << bitToChange);
    } else if (reservoirId == RESERVOIR_TR) { // Uses bits 3,2,1,0 of specialElectrodesRight
        bitToChange = 3 - electrodeInReservoir;
        if (on) specialElectrodesRight |= (1 << bitToChange);
        else specialElectrodesRight &= ~(1 << bitToChange);
    } else if (reservoirId == RESERVOIR_BR) { // Uses bits 7,6,5,4 of specialElectrodesRight
        bitToChange = 7 - electrodeInReservoir;
        if (on) specialElectrodesRight |= (1 << bitToChange);
        else specialElectrodesRight &= ~(1 << bitToChange);
    }
}
// ... existing code ...

// update dispenseSequenceAndPlaceDrop TL manual sequence to use helper calls instead of bit ops
if (reservoirId == RESERVOIR_TL) {
        println("Executing Top-Left Manual Dispense Sequence (corrected mapping)...");
        // Ensure TL special bits start cleared
        for (int i=0;i<4;i++) setReservoirElectrode(RESERVOIR_TL,i,false);
        electrodes[targetX][targetY]=false;

        // Frame 1: electrode 3 ON
        setReservoirElectrode(RESERVOIR_TL,3,true);
        transmit();delay(sequenceFrameDelay);

        // Frame 2: electrodes 3 and 2 ON
        setReservoirElectrode(RESERVOIR_TL,2,true);
        transmit();delay(sequenceFrameDelay);

        // Frame 3: electrodes 0,1,2 ON; electrode3 OFF
        setReservoirElectrode(RESERVOIR_TL,3,false);
        setReservoirElectrode(RESERVOIR_TL,0,true);
        setReservoirElectrode(RESERVOIR_TL,1,true);
        transmit();delay(sequenceFrameDelay);

        // Frame 4: only electrode 0 ON, others OFF; turn on main grid target
        setReservoirElectrode(RESERVOIR_TL,1,false);
        setReservoirElectrode(RESERVOIR_TL,2,false);
        electrodes[targetX][targetY]=true;
        transmit();delay(sequenceFrameDelay);

        // Frame 5: electrodes 2 and 3 ON again (0 OFF)
        setReservoirElectrode(RESERVOIR_TL,0,false);
        setReservoirElectrode(RESERVOIR_TL,2,true);
        setReservoirElectrode(RESERVOIR_TL,3,true);
        transmit();delay(sequenceFrameDelay);

        // Frame 6: only electrode 3 ON
        setReservoirElectrode(RESERVOIR_TL,2,false);
        transmit();delay(sequenceFrameDelay);

        // Final: turn off all TL electrodes, leave drop on grid
        for (int i=0;i<4;i++) setReservoirElectrode(RESERVOIR_TL,i,false);
        transmit();delay(100);
        println("Top-Left dispense complete (corrected).");
} 