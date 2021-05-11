# Flows of the Pilot Monitoring
___
### Preflight

* Check FMGC data insertion (the script doesn't actually check anything, it just cycles through the MCDU pages)
* Set up the EFIS

#### Trigger:

Fill out the PERF and INIT B pages
___

### After start

* Arm the ground spoilers
* Set takeoff flaps
* Set the takeoff pitch trim

#### Trigger:

At least one engine running and the engine mode selector switch in the NORM position for at least 4 seconds.
___

### Flight controls check

* PM will announce 'full left', 'full right', 'neutral' etc.
The aileron and elevator checks need to be performed before the rudder check.

#### Trigger:

##### voice_control = 1:
Say 'Flight control check'<br><br>
##### voice_control = 0:

Full left or full right aileron deflection/
full up or full down elevator deflection
___

### Brake check

Apply some brakes and the PM will announce 'pressure zero'

#### Trigger:

##### voice_control = 1:
Say 'Brake check' during taxi with the ground speed  below 3 knots<br><br>
##### voice_control = 0:
The first brake application during taxi with the ground speed below 3 knots
___
**Note: you can do the brake and flight control checks in any order.**
___
### During taxi

* Weather radar SYS switch 1 or 2
* Weather radar PWS switch AUTO
* AUTO BRK MAX
* Press TO CONFIG button

#### Trigger:

As soon as the brake and flight controls checks are completed
___
### Lineup

* Transponder ON/OFF switch ON
* Transponder MODE switch TARA
* Optionally, turn the packs off

#### Trigger:

##### voice_control = 1:
>* ###### *lineup\_trigger = 1*
   Say 'lineup procedure'
   <br><br>

>* ###### *lineup\_trigger = 2*
   Cycle the seat belts sign switch twice within two seconds.
<br><br>
##### voice_control = 0:
Cycle the seat belts sign switch twice within two seconds  
___
Note: To decide whether to turn the packs off, the script first looks for a performance request in the ATSU log. If it finds a performance request and the packs are off in it, the PM will turn the packs off. Otherwise, he will turn them off or leave them in their current setting when *packs\_on\_takeoff* is set to 0 and 1, respectively.
___
### Takeoff

* MIP chrono elapsed time switch RUN
* Press the glareshield CHRONO button on PM's side

#### Trigger:

##### voice_control = 1:
Say 'Takeoff'<br><br>
##### voice_control = 0:
Thrust levers in FLX or TOGA and landing lights on
___
### Takeoff roll callouts

if *takeoff_FMA_readout=1*, the copilot will wait for your FMA readout before announcing 'thrust set'. Example: "MAN FLEX 64 SRS runway autothrust blue".

* 'Thrust set'
* 'One hundred'
* 'V1 (if it's not played by the aircraft itself)
* 'Rotate'
* 'Positive climb'
___
* Retract the gear

#### Voice command:

'Gear up'
___
### After takeoff

* Select the packs back on if they were turned off for takeoff

* Voice commands *(if voice\_control=1)*:
>* *'Flaps two'*
>* *'Flaps one'*
>* *'Flaps up' or 'flaps zero'*

Once the flaps are retracted:

* Disarm the ground spoilers

#### Trigger:

Move the thrust levers back to CLB.
___
### Climbing through 10000

* Retract the landing lights
* On PM'S MCDU:
   * Clear the RADNAV page
   * Copy the active flight plan on the SEC F-PLN page
* On PM's side EFIS:
   * Select ARPT
   * ND range to 160
   * VOR/ADF switches to VOR
___
### Descending through 10000

* Landing lights ON
* Seat belts sign switch ON
* On PM's side EFIS:
   * Select LS if an ILS or LOC approach has been selected in the MCDU
   * Select CSTR

* On PM's side MCDU:
   * Look at the RADNAV page for 5 seconds
   * Go to the PROG page 

* Voice commands become available:

> * 'Gear down'  
> * 'Flaps one'  
> * 'Flaps two'  
> * 'Flaps three'  
> * 'Flaps full'  
___
### Landing roll callouts

* 'Spoilers'
* 'Reverse green'
* 'Decel'
* '70 knots'
___
### After landing

* Retract the flaps
* Transponder mode switch STBY
* MIP chrono elapsed time switch STP
* Press the chrono button on PM's side glareshield
* Strobe light switch AUTO
* Runway turnoff light switch OFF
* Landing lights switches OFF
* Nose light switch TAXI
* Weather radar SYS switch OFF
* Weather radar PWS switch OFF
* *option FDs\_off\_after\_landing:*
>* *Turn off both  flight directors if the option is set to 1 or turn them back on if it is set to 0.*
* Select LS off on both sides
* Disable the 'bird' mode if it's active
* *pack2\_off\_after\_landing=1:*
>* *Turn off pack 2*
* Start the APU unless you told not to
* Voice command 'Taxi light off' becomes available

#### Trigger:

##### voice_control = 1:
>* ###### *after\_landing\_trigger = 1*
   Say 'After landing' or 'After landing, delay APU'.  
   Saying 'delay APU' can be delayed until the PM is just about to start the APU.  
   If you chose not to start the APU during the after landing procedure, you can say 'Start APU' at any time until the engines are shut down.<br><br>

>* ###### *after\_landing\_trigger = 2*
   Disarm the ground spoilers. After that, you may say 'delay APU'.
<br><br>

##### voice_control = 0:

Disarm the ground spoilers

___

### Parking

* Anti-ice OFF
* APU bleed ON
* Fuel pumps OFF
If checklists are enabled, wait until the parking checklist is completed.
Wait until external power is available
* Connect external power
* APU bleed OFF
* APU off

#### Trigger:

Engines off
___

### Securing the Aircraft

* Crew oxygen supply OFF
* External lights OFF
* APU and APU bleed OFF
* Batteries OFF

#### Trigger:

ADIRS off