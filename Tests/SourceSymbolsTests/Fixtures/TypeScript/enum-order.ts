enum E {
  A = (() => { const B = 1; return B; })(),
  B = 2,
  C = (() => { function nested() { const local = 3; return local; } return nested(); })(),
  D = 4
}
