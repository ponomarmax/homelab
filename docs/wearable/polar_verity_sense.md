
# Polar Verity Sense

## Role in the project

Polar Verity Sense is the initial production baseline for:
- heart rate
- PPI / RR-like timing when available
- accelerometer
- future motion-related validation

## Why Polar first

- simpler signal family than Muse
- better baseline for cardio and movement
- better fit for the first end-to-end vertical slice

## Planned implementation order

1. online HR
2. HR upload to backend
3. raw storage
4. HR visualization
5. PPI
6. ACC
7. offline exploration later

## Notes

The backend transport contracts should not be Polar-specific even though Polar is the first implementation target.