Summary:
  Total:        60.0243 secs
  Slowest:      0.2173 secs
  Fastest:      0.0111 secs
  Average:      0.0713 secs
  Requests/sec: 224.2092
  
  Total data:   457572 bytes
  Size/request: 34 bytes

Response time histogram:
  0.011 [1]     |
  0.032 [345]   |■■■
  0.052 [3577]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.073 [3056]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.094 [4255]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.114 [1870]  |■■■■■■■■■■■■■■■■■■
  0.135 [257]   |■■
  0.155 [80]    |■
  0.176 [14]    |
  0.197 [2]     |
  0.217 [1]     |


Latency distribution:
  10% in 0.0493 secs
  25% in 0.0516 secs
  50% in 0.0679 secs
  75% in 0.0878 secs
  90% in 0.0978 secs
  95% in 0.1060 secs
  99% in 0.1286 secs

Details (average, fastest, slowest):
  DNS+dialup:   0.0000 secs, 0.0111 secs, 0.2173 secs
  DNS-lookup:   0.0000 secs, 0.0000 secs, 0.0000 secs
  req write:    0.0000 secs, 0.0000 secs, 0.0045 secs
  resp wait:    0.0706 secs, 0.0110 secs, 0.2168 secs
  resp read:    0.0007 secs, 0.0000 secs, 0.0440 secs

Status code distribution:
  [200] 13458 responses



  Requests/sec: 224.2092
  50% in 0.0679 secs
  95% in 0.1060 secs



Summary:
  Total:        60.0702 secs
  Slowest:      0.5574 secs
  Fastest:      0.0115 secs
  Average:      0.0680 secs
  Requests/sec: 235.0916
  
  Total data:   480148 bytes
  Size/request: 34 bytes

Response time histogram:
  0.011 [1]     |
  0.066 [6609]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.121 [7433]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.175 [48]    |
  0.230 [12]    |
  0.284 [6]     |
  0.339 [3]     |
  0.394 [9]     |
  0.448 [0]     |
  0.503 [0]     |
  0.557 [1]     |


Latency distribution:
  10% in 0.0558 secs
  25% in 0.0581 secs
  50% in 0.0679 secs
  75% in 0.0757 secs
  90% in 0.0837 secs
  95% in 0.0908 secs
  99% in 0.1106 secs

Details (average, fastest, slowest):
  DNS+dialup:   0.0000 secs, 0.0115 secs, 0.5574 secs
  DNS-lookup:   0.0000 secs, 0.0000 secs, 0.0000 secs
  req write:    0.0000 secs, 0.0000 secs, 0.0005 secs
  resp wait:    0.0673 secs, 0.0113 secs, 0.5562 secs
  resp read:    0.0007 secs, 0.0000 secs, 0.0477 secs

Status code distribution:
  [200] 14122 responses



RPS=235.0916 Avg= P50=in P95=in

**Bench (i7-9700/32GB, Docker, workers=2, n≈∞, c=16, 60s)**
- Requests/sec ≈ <RPS>
- Latency: Avg ≈ <Avg>, P50 ≈ <P50>, P95 ≈ <P95>
- 失敗 0 を確認


