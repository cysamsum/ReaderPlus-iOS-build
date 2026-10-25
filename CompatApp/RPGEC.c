// C adaptation of rany2/edge-tts drm.py, bd44c1d; rany and contributors.
// SPDX-License-Identifier: LGPL-3.0-only
#include "RPGEC.h"
#include <stdio.h>
#include <string.h>
static const uint32_t initial[8]={0x6A09E667,0xBB67AE85,0x3C6EF372,0xA54FF53A,0x510E527F,0x9B05688C,0x1F83D9AB,0x5BE0CD19};
static const uint32_t partial[8]={0xFD9FBEA2,0x91243CE7,0xBE499094,0xCD2E1E0A,0x6C006F49,0x04BD35AB,0xFEB0A7E4,0x03EFFBD2};
static const uint32_t schedule[14]={0xEB24BF9E,0x1558691F,0xA0C09EE2,0x0CFA32BA,0xA622EE8C,0xD1DD9491,0xC0DD25A0,0xF9E70AB6,0xF0C31573,0x7058CE4E,0x7188E606,0x00E5AB33,0xD258B060,0x72766564};
static const uint32_t constants[64]={
0x428A2F98,0x71374491,0xB5C0FBCF,0xE9B5DBA5,0x3956C25B,0x59F111F1,0x923F82A4,0xAB1C5ED5,
0xD807AA98,0x12835B01,0x243185BE,0x550C7DC3,0x72BE5D74,0x80DEB1FE,0x9BDC06A7,0xC19BF174,
0xE49B69C1,0xEFBE4786,0x0FC19DC6,0x240CA1CC,0x2DE92C6F,0x4A7484AA,0x5CB0A9DC,0x76F988DA,
0x983E5152,0xA831C66D,0xB00327C8,0xBF597FC7,0xC6E00BF3,0xD5A79147,0x06CA6351,0x14292967,
0x27B70A85,0x2E1B2138,0x4D2C6DFC,0x53380D13,0x650A7354,0x766A0ABB,0x81C2C92E,0x92722C85,
0xA2BFE8A1,0xA81A664B,0xC24B8B70,0xC76C51A3,0xD192E819,0xD6990624,0xF40E3585,0x106AA070,
0x19A4C116,0x1E376C08,0x2748774C,0x34B0BCB5,0x391C0CB3,0x4ED8AA4A,0x5B9CCA4F,0x682E6FF3,
0x748F82EE,0x78A5636F,0x84C87814,0x8CC70208,0x90BEFFFA,0xA4506CEB,0xBEF9A3F7,0xC67178F2};
static const uint32_t coeff[14][2]={
{0xE82E91B1,0xB32700D0},{0x44DE24C6,0x88DFF51D},{0x3BEB65BC,0x29514038},{0xC89C5933,0xB328CBDF},
{0x8D1EC211,0xD405B4D5},{0x314EF5D5,0x26E55F3C},{0xE92491B1,0x607801C6},{0xF0A5B9D5,0x82B2C1FB},
{0x06064CF3,0xFA51A3DA},{0xDA79FA60,0x207CC464},{0xBED20560,0x3C3C74F3},{0x89F9C9F8,0xD2D14B61},
{0x35FA38C6,0xBB04A2C1},{0xCB49E3C6,0xC5626167}};
static uint32_t r(uint32_t x,int n){return (x>>n)|(x<<(32-n));}
static uint32_t sw(uint32_t x){return (x<<16)|(x>>16);}
static uint32_t s0(uint32_t x){return r(x,7)^r(x,18)^(x>>3);}
static uint32_t s1(uint32_t x){return r(x,17)^r(x,19)^(x>>10);}
static uint32_t be(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static uint32_t le(const uint8_t *p){return (uint32_t)p[3]<<24|(uint32_t)p[2]<<16|(uint32_t)p[1]<<8|p[0];}
static void expand(uint32_t w[64],int first){for(int i=first;i<64;i++)w[i]=s1(w[i-2])+w[i-7]+s0(w[i-15])+w[i-16];}
static void rounds(const uint32_t st[8],const uint32_t w[64],int first,uint32_t out[8]){
 uint32_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4],f=st[5],g=st[6],h=st[7];
 for(int i=first;i<64;i++){
  uint32_t k=(first==14&&i==14)?0xC9DC06A7:constants[i];
  uint32_t t1=h+(r(e,6)^r(e,11)^r(e,25))+((e&f)^(~e&g))+k+w[i];
  uint32_t t2=(r(a,2)^r(a,13)^r(a,22))+((a&b)^(a&c)^(b&c));
  h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
 }
 uint32_t values[8]={a,b,c,d,e,f,g,h};memcpy(out,values,sizeof(values));
}
static void digest(const uint8_t *data,size_t count,uint8_t out[32]){
 uint32_t w[64]={0},work[8],state[8];w[14]=(uint32_t)data[0]<<16|(uint32_t)data[1]<<8|data[2];w[15]=be(data+3);
 for(int i=16;i<30;i++){
  uint32_t v=schedule[i-16];if(i-2>=14)v+=s1(w[i-2])^(i==16?0x000B92C0:0);
  if(i-7>=14)v+=w[i-7];if(i-15>=14)v+=s0(w[i-15])^(i==29?0x059C0B80:0);w[i]=v;
 }
 w[30]=s1(w[28])+w[23]+s0(w[15])+w[14]+0xC9DC06A7-constants[14];expand(w,31);
 rounds(partial,w,14,work);for(int i=0;i<8;i++)state[i]=initial[i]+work[i];
 size_t length=57+count,n=count-7;uint8_t padded[256]={0};memcpy(padded,data+7,n);padded[n++]=0x80;
 n+=(55+64-length%64)%64;uint64_t bits=(uint64_t)length*8;
 for(int i=7;i>=0;i--)padded[n++]=(uint8_t)(bits>>(i*8));
 for(size_t offset=0;offset<n;offset+=64){for(int i=0;i<16;i++)w[i]=be(padded+offset+i*4);expand(w,16);rounds(state,w,0,work);for(int i=0;i<8;i++)state[i]+=work[i];}
 for(int i=0;i<8;i++)for(int j=0;j<4;j++)out[i*4+j]=(uint8_t)(state[i]>>(24-j*8));
}
static void cs64(const uint8_t *data,size_t count,const uint8_t hash[32],uint8_t out[8]){
 uint32_t a=le(hash)|1,b=le(hash+4)|1,factors[2]={a*0x82893933,b*0x82893933};
 uint32_t terms[64]={0},offsets[64]={0};size_t n=14;
 for(int i=0;i<14;i++){terms[i]=coeff[i][0]*factors[i%2];offsets[i]=coeff[i][1];}
 uint8_t padded[128]={0};memcpy(padded+1,data,count);size_t words=(count+1+7)/8*2;
 for(size_t i=0;i<words;i++){
  uint32_t v=le(padded+i*4),t=v*(i%2?b:a),o=sw(v)*(i%2?0xC31713DB:0xEF0569FB);
  if(i==0){t+=0xF2F90B1A*factors[0];o+=0x0B1A0000;}terms[n]=t;offsets[n++]=o;
 }
 uint32_t sa=0,sl=0,state=0,acc=0;
 for(size_t i=0;i<n;i+=2){
  uint32_t x=terms[i],y=terms[i+1],q=sw(offsets[i]+x)*0x76F50F34;sa+=sw(q)*0xC3EFEA97+q;
  q=sw(offsets[i+1]+y)*0x1881CE3C;sl=sw(q)*0x35BD1EC9+q;sa+=sl;
  state=state*a+x;state=sw(state)*0xCF98B111;state=sw(state)*0x87085B9F;state=sw(state)*0x12CEB96D;state=sw(state)*0x257E1D83;acc+=state;
  uint32_t t=state*b+y;t=sw(t)*0xA27416F5;t=sw(t)*0xD38396FF;state=sw(sw(t)*0x7C932B89)*0xBFA49F69;acc+=state;
 }
 uint32_t v[2]={sl^state,sa^acc};for(int i=0;i<2;i++)for(int j=0;j<4;j++)out[i*4+j]=(uint8_t)(v[i]>>(j*8));
}
void rp_gec_v2(int64_t unixSeconds,char output[82]){
 int64_t seconds=unixSeconds+INT64_C(11644473600);int64_t ticks=(seconds-seconds%300)*INT64_C(10000000);
 char input[96];snprintf(input,sizeof(input),"%lld6A5AA1D4EAFF4E9FB37E23D68491D6F4",(long long)ticks);
 uint8_t hash[32],cs[8];size_t n=strlen(input);digest((const uint8_t*)input,n,hash);cs64((const uint8_t*)input,n,hash,cs);
 for(int i=0;i<8;i++)sprintf(output+i*2,"%02X",cs[i]);output[16]='-';
 for(int i=0;i<32;i++)sprintf(output+17+i*2,"%02X",hash[i]);output[81]=0;
}
