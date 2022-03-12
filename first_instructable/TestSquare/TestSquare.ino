float x;
uint32_t k;
int i;

void setup() {
  x = 2;
  for(i=0; i<1000; i++) {
    x = x*x;
  }
  x = 2;
  for(i=0; i<1000; i++) {
    k = *(uint32_t *) & x;
    k <<= 1;
    k -= 0x3f748868;
    k &= 0x7fffffff;
    x = *(float*)& k;
  }

}

void loop() {

}
