#include <avr/io.h>
#include <stdfix.h>
 
extern "C"{ 
  volatile accum fx1, fx2, fx3;
}
volatile float fl1, flt2, fl3;

void setup() {
  fx2 = 2.33K;
  fx3 = 0.66K;
  flt2 = 2.33;
  fl3 = 0.66;

}

void loop() {
   
  fx1 = fx2 + fx3;
  fl1 = fl2 + fl3;
 
  fx1 = fx2 - fx3;
  fl1 = fl2 - fl3;
 
  fx1 = fx2 * fx3;
  fl1 = fl2 * fl3;
 
  fx3 = fx2 / fx3;
  fl3 = fl2 / fl3;
 
  //fl1 = (float)fx3;
}
