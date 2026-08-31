Benchmark

Smoke run for scenario and documentation verification. Run `mix bench` for stable local measurements.

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>macOS</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Apple M4 Max</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">16</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">128 GB</td>
  </tr><tr>
    <th style="white-space: nowrap">Elixir Version</th>
    <td style="white-space: nowrap">1.20.2</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">28.5</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">10 ms</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">0 ns</td>
  </tr>
</table>

## Statistics



Run Time

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Deviation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">encode artifact</td>
    <td style="white-space: nowrap; text-align: right">43.62 K</td>
    <td style="white-space: nowrap; text-align: right">22.93 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.93%</td>
    <td style="white-space: nowrap; text-align: right">21.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.15 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode artifact</td>
    <td style="white-space: nowrap; text-align: right">27.29 K</td>
    <td style="white-space: nowrap; text-align: right">36.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.68%</td>
    <td style="white-space: nowrap; text-align: right">35.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">51.18 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render text scalar</td>
    <td style="white-space: nowrap; text-align: right">19.70 K</td>
    <td style="white-space: nowrap; text-align: right">50.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.89%</td>
    <td style="white-space: nowrap; text-align: right">49.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">76.74 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render text 100-item loop</td>
    <td style="white-space: nowrap; text-align: right">3.20 K</td>
    <td style="white-space: nowrap; text-align: right">312.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;270.84%</td>
    <td style="white-space: nowrap; text-align: right">121.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4934.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">compile text</td>
    <td style="white-space: nowrap; text-align: right">0.198 K</td>
    <td style="white-space: nowrap; text-align: right">5056.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.22%</td>
    <td style="white-space: nowrap; text-align: right">5056.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5243.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">compile MJML email</td>
    <td style="white-space: nowrap; text-align: right">0.149 K</td>
    <td style="white-space: nowrap; text-align: right">6704.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.30%</td>
    <td style="white-space: nowrap; text-align: right">6704.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">6908.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render email channels</td>
    <td style="white-space: nowrap; text-align: right">0.0536 K</td>
    <td style="white-space: nowrap; text-align: right">18671.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">18671.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">18671.33 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">encode artifact</td>
    <td style="white-space: nowrap;text-align: right">43.62 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">decode artifact</td>
    <td style="white-space: nowrap; text-align: right">27.29 K</td>
    <td style="white-space: nowrap; text-align: right">1.6x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render text scalar</td>
    <td style="white-space: nowrap; text-align: right">19.70 K</td>
    <td style="white-space: nowrap; text-align: right">2.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render text 100-item loop</td>
    <td style="white-space: nowrap; text-align: right">3.20 K</td>
    <td style="white-space: nowrap; text-align: right">13.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">compile text</td>
    <td style="white-space: nowrap; text-align: right">0.198 K</td>
    <td style="white-space: nowrap; text-align: right">220.56x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">compile MJML email</td>
    <td style="white-space: nowrap; text-align: right">0.149 K</td>
    <td style="white-space: nowrap; text-align: right">292.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">render email channels</td>
    <td style="white-space: nowrap; text-align: right">0.0536 K</td>
    <td style="white-space: nowrap; text-align: right">814.35x</td>
  </tr>

</table>