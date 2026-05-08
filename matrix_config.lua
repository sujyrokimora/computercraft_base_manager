return {
  name = "main_matrix",
  group = "power",
  machine = "matrix",

  matrixPeripheralType = "inductionPort",

  -- <= 20% sends one reactor ON request
  -- >= 80% sends one reactor OFF request
  batteryStartAt = 0.20,
  batteryStopAt = 0.80
}
