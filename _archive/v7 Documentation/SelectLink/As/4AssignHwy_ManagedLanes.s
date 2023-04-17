*(echo 4AssignHwy_ManagedLanes.s > 4AssignHwy_ManagedLanes.txt)  ;In case TP+ crashes during batch, this will halt process & help identify error location.
*(DEL *.PRN)

	;This is a dummy file used to calculate the time it takes to run script
	*(ECHO dummy file to calculate elapsed time > _timchk2.txt)
	  
READ FILE = '..\..\0GeneralParameters.block'
READ FILE = '..\..\1ControlCenter.block'

TripTableFactor   = 1.0  ;Default to 1.0  - Only use for specialized applications

  
MilesPerCar = 200000
/* **************************************************************************
File:       4AssignHwy.s
Purpose:    1. Take the trip tables assigned to autos by the Mode Choice 
               and convert them to directional OD tables by period. (Some
               are person-trips and some are vehicle-trips).
            2. Assign the OD tables by period.
*************************************************************************** */


:Step1

if (OptimizeLanes_Distrib <> 0)
RUN PGM=HWYNET
  FILEI NETI = @ParentDir@@DDir@@Do@@unloadednetprefix@.load.net
  FILEO NETO = @ParentDir@@TempDir@@ATmp@tmp_start.net
ENDRUN
else
RUN PGM=HWYNET
  FILEI NETI = @ParentDir@@IDir@@Io@@unloadednetprefix@.net
  FILEO NETO = @ParentDir@@TempDir@@ATmp@tmp_start.net
ENDRUN
endif


LOOP iter=1,3,1

;goto :step6
if (iter = 1) goto :AfterOptimize  ;must first run a basic 4-pd assign.
if (iter > 1) ;assign again, if optimizing, but for Optimized lanes.
  if (OptimizeLanes_Final = 0)
    goto :EndAssign
  else

; ******************************************************************************
; Purpose:  Adjust lanes up if VC is too high, and down if too low. 
;           (If user specifies this test).
; ******************************************************************************
RUN PGM=HWYNET
  FILEI NETI = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.load.@AssignType@.net 
  FILEO NETO = @ParentDir@@TempDir@@ATmp@tmp_start.net       ;can't write the file that I read, so use intermediate
      
  PHASE = LINKMERGE
    
    LANES@iter@ = LI.1.lanes
    
  if (ft <> 1 || lanes <> 7)
    _cap = (LI.1.cap1hr1ln * LI.1.lanes * 3 * @OptimizeLanes_TargetVC@) ; 3hrs; lowering cap to target will cause it to build more lanes (i.e. cap threshold)
    if (LI.1.am_vol > LI.1.pm_vol)
      _highvol = LI.1.am_vol
      _highvc  = LI.1.am_vc
    else
      _highvol = LI.1.pm_vol
      _highvc  = LI.1.pm_vc
    endif
    _VolCapDif = _highvol - _cap
    _LaneChange = _VolCapDif / (LI.1.cap1hr1ln * 3) ;3hrs
    
    
    if     (_highvc > 1.4)  ;anticipate high latent demand and add additional
      _lanefac = 1.6
    elseif (_highvc <= 1.4 && _highvc > 1.0)
      _lanefac = 1.4
    else
      _lanefac = 1.0
    endif
    
    LANES = LI.1.LANES + (_LaneChange * _lanefac)
    if (LANES <= .5)  LANES = .5
    
    if (LANES >= 4 && LI.1.ft < 29 && @OptimizeLanes_GradeSeparate@ <> 0)  ;if it wants to make lanes too big, turn it into freeway.
      cap1hr1ln = 2115
      ft = 31
      LANES = LANES * (2/5) ;a little less than 1/2 a freeway lane is comparable to a regular arterial lane
      sff     = 65  ;redefine speeds for distribution.
      am_spd1 = 60
      md_spd1 = 60
      am_spd2 = 60
      md_spd2 = 60
      am_spd3 = 60
      md_spd3 = 60
    endif
  endif
      
  ENDPHASE

ENDRUN

  endif
endif

:AfterOptimize
if (RunFinalAssignFromPM <> 0) 
  goto :stepPM
endif

;**************************************************************************
;Purpose:	Assign four trip tables (AM,Mid,PM,Eve) to a single network. 
;**************************************************************************

if (runselectlink == 1)
  selectlink = ' '
else
  selectlink = ';'
endif

;**************************************************************************
;Purpose:	Assign AM trip table to loaded network
;**************************************************************************
:StepAM
if (PathsAM = 0)
  Paths_Y = ';'
  Paths_N = ' '
else
  Paths_Y = ' '
  Paths_N = ';'
endif
RUN PGM=HWYLOAD
  ZONEMSG       = @ZoneMsgRate@  ;reduces print messages in TPP DOS. (i.e. runs faster).  ;reduces print messages in TPP DOS. (i.e. runs faster).
  FILEI MATI[1] = @ParentDir@@TempDir@@ATmp@am3hr_managed.mtx  ;trip tables by purpose & total
  FILEI NETI    = @ParentDir@@TempDir@@ATmp@tmp_start.net       
  FILEI TURNPENI = @ParentDir@@IDir@@Io@turnpenalties.txt
  FILEO NETO    = @ParentDir@@TempDir@@ATmp@tmp_am.net	   ; alternate tmpa & tmpb until final network achieved
  @Paths_Y@ FILEO PATHO[1]=@ParentDir@@TempDir@@ATmp@AM_Paths.@RID@.@PathsGroupField@.pth,  costdec=@PathsCostDec@, iters=@PathsIters@ 
  @GenerateAM3hrAoTurnvolo@ TURNVOLO = @ParentDir@@ADir@@Ao@Ao_AMturnvol.Bin, format=BIN
  @GenerateAM3hrAoTurnvolo@ TURNS @TurnIntersectionsAo@ 
  @selectlink@ FILEO MATO    = @ParentDir@@TempDir@@ATmp@SelectLink_AM.mtx, mo=11-15, name=DA_NON,SR_NON,SR_HOV,DA_TOL,SR_TOL


  hrsinperiod   = 3
  whatperiod    = 1
  toll_cost = @FT40_cost_Pk@
  value_of_time = @Auto_value_Pk@

  PARAMETERS GAP= .00001  ;convergence criteria (system cost)
  PARAMETERS RMSE= 1  ;convergence criteria (link-based)
  PARAMETERS MAXITERS = 50  ;maximum iterations

  READ FILE     = @ParentDir@@ADir@@As@block\4pd_mainbody_managedlanes.block
ENDRUN

;**************************************************************************
;Purpose:	Assign Mid-day trip table to loaded network
;**************************************************************************
:StepMD
  Paths_Y = ';'
  Paths_N = ' '
RUN PGM=HWYLOAD
  ZONEMSG        = @ZoneMsgRate@  ;reduces print messages in TPP DOS. (i.e. runs faster).  ;reduces print messages in TPP DOS. (i.e. runs faster).
  FILEI MATI[1]  = @ParentDir@@TempDir@@ATmp@md6hr_managed.mtx  ;trip tables by purpose & total
  FILEI NETI     = @ParentDir@@TempDir@@ATmp@tmp_am.net	   ; alternate tmpa & tmpb until final network achieved
  FILEI TURNPENI = @ParentDir@@IDir@@Io@turnpenalties.txt
  FILEO NETO     = @ParentDir@@TempDir@@ATmp@tmp_md.net	   ; alternate tmpa & tmpb until final network achieved
  @selectlink@ FILEO MATO    = @ParentDir@@TempDir@@ATmp@SelectLink_MD.mtx, mo=11-15, name=DA_NON,SR_NON,SR_HOV,DA_TOL,SR_TOL
  hrsinperiod    = 6
  whatperiod     = 2
  toll_cost = @FT40_cost_Ok@
  value_of_time = @Auto_value_Ok@

  PARAMETERS GAP= .00001  ;convergence criteria (system cost)
  PARAMETERS RMSE= 1  ;convergence criteria (link-based)
  PARAMETERS MAXITERS = 20  ;maximum iterations

  READ FILE      = @ParentDir@@ADir@@As@block\4pd_mainbody_managedlanes.block
ENDRUN

;**************************************************************************
;Purpose:	Assign PM trip table to loaded network
;**************************************************************************
:StepPM
if (PathsPM = 0)
  Paths_Y = ';'
  Paths_N = ' '
else
  Paths_Y = ' '
  Paths_N = ';'
endif
RUN PGM=HWYLOAD
  ZONEMSG       = @ZoneMsgRate@  ;reduces print messages in TPP DOS. (i.e. runs faster).  ;reduces print messages in TPP DOS. (i.e. runs faster).
  FILEI MATI[1] = @ParentDir@@TempDir@@ATmp@pm3hr_managed.mtx  ;trip tables by purpose & total
  FILEI NETI    = @ParentDir@@TempDir@@ATmp@tmp_md.net	   ; alternate tmpa & tmpb until final network achieved
  FILEI TURNPENI = @ParentDir@@IDir@@Io@turnpenalties.txt
  FILEO NETO    = @ParentDir@@TempDir@@ATmp@tmp_pm.net	   ; alternate tmpa & tmpb until final network achieved
  @Paths_Y@ FILEO PATHO[1]=@ParentDir@@TempDir@@ATmp@PM_Paths.@RID@.@PathsGroupField@.pth,  costdec=@PathsCostDec@, iters=@PathsIters@ 
  @GeneratePM3hrAoTurnvolo@ TURNVOLO = @ParentDir@@ADir@@Ao@Ao_PMturnvol.Bin, format=BIN
  @GeneratePM3hrAoTurnvolo@ TURNS @TurnIntersectionsAo@ 
  @selectlink@ FILEO MATO    = @ParentDir@@TempDir@@ATmp@SelectLink_PM.mtx, mo=11-15, name=DA_NON,SR_NON,SR_HOV,DA_TOL,SR_TOL  
  hrsinperiod   = 3
  whatperiod    = 3
  toll_cost = @FT40_cost_Pk@
  value_of_time = @Auto_value_Pk@

  PARAMETERS GAP= .00001  ;convergence criteria (system cost)
  PARAMETERS RMSE= 1  ;convergence criteria (link-based)
  PARAMETERS MAXITERS = 50  ;maximum iterations

  READ FILE     = @ParentDir@@ADir@@As@block\4pd_mainbody_managedlanes.block
ENDRUN

;**************************************************************************
;Purpose:	Assign evening trip table loaded network
;**************************************************************************
:StepEV
  Paths_Y = ';'
  Paths_N = ' '
RUN PGM=HWYLOAD
  ZONEMSG       = @ZoneMsgRate@  ;reduces print messages in TPP DOS. (i.e. runs faster).  ;reduces print messages in TPP DOS. (i.e. runs faster).
  FILEI MATI[1] = @ParentDir@@TempDir@@ATmp@ev12hr_managed.mtx  ;trip tables by purpose & total
  FILEI NETI    = @ParentDir@@TempDir@@ATmp@tmp_pm.net	   ; alternate tmpa & tmpb until final network achieved
  FILEI TURNPENI = @ParentDir@@IDir@@Io@turnpenalties.txt
  FILEO NETO    = @ParentDir@@TempDir@@ATmp@tmp_ev.net	   ; alternate tmpa & tmpb until final network achieved
  @selectlink@ FILEO MATO    = @ParentDir@@TempDir@@ATmp@SelectLink_EV.mtx, mo=11-15, name=DA_NON,SR_NON,SR_HOV,DA_TOL,SR_TOL

  hrsinperiod   = 12
  whatperiod    = 4
  toll_cost = @FT40_cost_Ok@
  value_of_time = @Auto_value_Ok@

  PARAMETERS GAP= .00001  ;convergence criteria (system cost)
  PARAMETERS RMSE= 1  ;convergence criteria (link-based)
  PARAMETERS MAXITERS = 20  ;maximum iterations

  READ FILE     = @ParentDir@@ADir@@As@block\4pd_mainbody_managedlanes.block
ENDRUN

; ******************************************************************************
; Purpose:  HWYLOAD won't let me name the volumes in the output network 
; anything but V_1, V_2, etc. So read them into HWYNET and write them 
; back out with the names I want
; ******************************************************************************
:Step6
RUN PGM=HWYNET
  FILEI NETI[1] = @ParentDir@@TempDir@@ATmp@tmp_ev.net	   ; alternate tmpa & tmpb until final network achieved
  FILEI NETI[2] = @ParentDir@@TempDir@@ATmp@tmp_ev.net	   ; alternate tmpa & tmpb until final network achieved
  FILEO NETO    = @ParentDir@@TempDir@@ATmp@tmp_final.net	   ; alternate tmpa & tmpb until final network achieved
  
  MERGE RECORD=F
  
  PHASE=INPUT, FILEI=li.2  ;UAG website FAQ says this is how you set ONEWAY.
    _temp=a
    a=b
    b=_temp
  ENDPHASE 
    
    
; ** Rounding examples:  The round() function rounds a tenth to the nearest integer.
; Here's an example to accomplish other types of rounding
; Round 1.4367 to 1.44:  1.4367*100=143.67,  round(143.67) = 144.  Divide result by 100 = 1.44
; Round 10495 to 10500:  10495/100=104.95,  round(104.95) = 105.  Multiply by 100 = 10500.

 AM_VOL      = round(V_1)
 AM_MNG      = 0 ;spacer, fill in later
 AM_100      = round(V_1/100)
 if (LI.1.V_1 >= LI.2.V_1)
   AM_100_HIGH     = round(LI.1.V_1/100)
 else
   AM_100_HIGH     = round(LI.2.V_1/100)
 endif
 AM_VOL2WY   = round(VT_1)
 
 AM_DAGP      = round(V1_1)
 AM_SRGP      = round(V2_1)
 AM_HOV       = round(V3_1)
 AM_DATOL     = round(V4_1)
 AM_SRTOL     = round(V5_1)

 AM_GP       = AM_DAGP  + AM_SRGP
 AM_toll     = AM_DATOL + AM_SRTOL

 AM_Time     = round(TIME_1*1000)/1000
 AM_SPD      = round((distance/TIME_1)*60*10)/10
 AM_VC       = round(VC_1*100)/100
 AM_VC_MNG   = 0 ;spacer
 if (LI.1.VC_1 >= LI.2.VC_1)
   AM_VC_HIGH     = round(LI.1.VC_1*100)/100
 else
   AM_VC_HIGH     = round(LI.2.VC_1*100)/100
 endif
 AM_HOVPCTE  = 0 ;spacer
 
 MD_VOL      = round(V_2)
 MD_MNG      = 0 ;spacer, fill in later
 MD_100      = round(MD_VOL/100)
 MD_VOL2WY   = round(VT_2)
 
 MD_DAGP      = round(V1_2)
 MD_SRGP      = round(V2_2)
 MD_HOV       = round(V3_2)
 MD_DATOL     = round(V4_2)
 MD_SRTOL     = round(V5_2)

 MD_GP       = MD_DAGP  + MD_SRGP
 MD_toll     = MD_DATOL + MD_SRTOL
  
 MD_Time     = round(TIME_2*1000)/1000
 MD_SPD      = round((distance/TIME_2)*60*10)/10
 MD_VC       = round(VC_2*100)/100
 
 PM_VOL     = round(V_3)
 PM_MNG      = 0 ;spacer, fill in later
 PM_100     = round(V_3/100)
 if (LI.1.V_3 >= LI.2.V_3)
   PM_100_HIGH     = round(LI.1.V_3/100)
 else
   PM_100_HIGH     = round(LI.2.V_3/100)
 endif
 PM_VOL2WY  = round(VT_3)
 
 PM_DAGP      = round(V1_3)
 PM_SRGP      = round(V2_3)
 PM_HOV       = round(V3_3)
 PM_DATOL     = round(V4_3)
 PM_SRTOL     = round(V5_3)

 PM_GP       = PM_DAGP  + PM_SRGP
 PM_toll     = PM_DATOL + PM_SRTOL
 
 PM_Time    = round(TIME_3*1000)/1000
 PM_SPD     = round((distance/TIME_3)*60*10)/10
 PM_VC      = round(VC_3*100)/100
 PM_VC_MNG   = 0 ;spacer
 if (LI.1.VC_3 >= LI.2.VC_3)
   PM_VC_HIGH     = round(LI.1.VC_3*100)/100
 else
   PM_VC_HIGH     = round(LI.2.VC_3*100)/100
 endif
 PM_HOVPCTE  = 0 ;spacer
 
 EV_VOL     = round(V_4)
 EV_MNG      = 0 ;spacer, fill in later
 EV_100     = round(EV_VOL/100)
 EV_VOL2WY  = round(VT_4)
 
 EV_DAGP      = round(V1_4)
 EV_SRGP      = round(V2_4)
 EV_HOV       = round(V3_4)
 EV_DATOL     = round(V4_4)
 EV_SRTOL     = round(V5_4)

 EV_GP       = EV_DAGP  + EV_SRGP
 EV_toll     = EV_DATOL + EV_SRTOL
 
 EV_Time    = round(TIME_4*1000)/1000
 EV_SPD     = round((distance/TIME_4)*60*10)/10
 EV_VC      = round(VC_4*100)/100
 
 DY_VOL     = AM_VOL + MD_VOL + PM_VOL + EV_VOL
 DY_MNG      = 0 ;spacer, fill in later
 DY_1000    = round(DY_VOL/1000)
 DY_VOL2WY  = AM_VOL2WY + MD_VOL2WY + PM_VOL2WY + EV_VOL2WY
 DY_2WY1000 = round(DY_VOL2WY/1000)	

 DY_DAGP    = AM_DAGP + MD_DAGP + PM_DAGP + EV_DAGP
 DY_SRGP    = AM_SRGP + MD_SRGP + PM_SRGP + EV_SRGP
 DY_HOV     = AM_HOV + MD_HOV + PM_HOV + EV_HOV
 DY_toll     = AM_DATOL + AM_SRTOL + MD_DATOL + MD_SRTOL + PM_DATOL + PM_SRTOL + EV_DATOL + EV_SRTOL
 DY_GP       = DY_DAGP   + DY_SRGP
 
if (DY_VOL = 0)
  DY_Time = .3 ;must be non-zero for future calcs
else
  DY_Time = round((((AM_VOL*AM_Time)+(MD_VOL*MD_Time)+(PM_VOL*PM_Time)+(EV_VOL*EV_Time)) / DY_VOL)*1000)/1000 ;Time=weighted average
endif
if (DY_Time = 0)
  DY_SPD = 26  ;must be non-zero for future calcs
else
  DY_SPD  = round((distance/DY_Time)*60*10)/10
endif	
  
@selectlink@ AM_select      = V11_1+V12_1+V13_1+V14_1+V15_1
@selectlink@ MD_select      = V11_2+V12_2+V13_2+V14_2+V15_2
@selectlink@ PM_select      = V11_3+V12_3+V13_3+V14_3+V15_3
@selectlink@ EV_select      = V11_4+V12_4+V13_4+V14_4+V15_4


@selectlink@ DY_select=AM_select+MD_select+PM_select+EV_select
ENDRUN

; ******************************************************************************
; Purpose:  Delete junk
; ******************************************************************************
:Step8
RUN PGM=HWYNET
  FILEI LINKI = @ParentDir@@TempDir@@ATmp@tmp_final.net,
    EXCLUDE   = V_1,V1_1,V2_1,V3_1,V4_1,V5_1,V6_1,V7_1,V8_1,V9_1,V10_1,  V11_1,V12_1,V13_1,V14_1,V15_1,V16_1,V17_1,V18_1, V19_1,V20_1,
    EXCLUDE   = V_2,V1_2,V2_2,V3_2,V4_2,V5_2,V6_2,V7_2,V8_2,V9_2,V10_2,  V11_2,V12_2,V13_2,V14_2,V15_2,V16_2,V17_2,V18_2, V19_2,V20_2,
    EXCLUDE   = V_3,V1_3,V2_3,V3_3,V4_3,V5_3,V6_3,V7_3,V8_3,V9_3,V10_3,  V11_3,V12_3,V13_3,V14_3,V15_3,V16_3,V17_3,V18_3, V19_3,V20_3, 
    EXCLUDE   = V_4,V1_4,V2_4,V3_4,V4_4,V5_4,V6_4,V7_4,V8_4,V9_4,V10_4,  V11_4,V12_4,V13_4,V14_4,V15_4,V16_4,V17_4,V18_4, V19_4,V20_4, 
    EXCLUDE   = VT_1,V1T_1,V2T_1,V3T_1,V4T_1,V5T_1,V6T_1,V7T_1,V8T_1,V9T_1,V10T_1,  V11T_1,V12T_1,V13T_1,V14T_1,V15T_1,V16T_1,V17T_1,V18T_1, 
    EXCLUDE   = VT_2,V1T_2,V2T_2,V3T_2,V4T_2,V5T_2,V6T_2,V7T_2,V8T_2,V9T_2,V10T_2,  V11T_2,V12T_2,V13T_2,V14T_2,V15T_2,V16T_2,V17T_2,V18T_2, 
    EXCLUDE   = VT_3,V1T_3,V2T_3,V3T_3,V4T_3,V5T_3,V6T_3,V7T_3,V8T_3,V9T_3,V10T_3,  V11T_3,V12T_3,V13T_3,V14T_3,V15T_3,V16T_3,V17T_3,V18T_3, 
    EXCLUDE   = VT_4,V1T_4,V2T_4,V3T_4,V4T_4,V5T_4,V6T_4,V7T_4,V8T_4,V9T_4,V10T_4,  V11T_4,V12T_4,V13T_4,V14T_4,V15T_4,V16T_4,V17T_4,V18T_4, 
    EXCLUDE   = TIME_1, TIME_2, TIME_3, TIME_4,  VC_1, VC_2, VC_3, VC_4,
    EXCLUDE   = VDT_1, VDT_2, VDT_3, VDT_4,   VHT_1, VHT_2, VHT_3, VHT_4,   CSPD_1, CSPD_2, CSPD_3, CSPD_4,
    EXCLUDE   = SPDPK, SPDOPK, CAPPK, CAPOPK, CAP24, S_AM, S_MD, S_EV, S_PM
  FILEO NETO  = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.detailed.net	
ENDRUN 

; ******************************************************************************
; Purpose:  Filter the detailed assignment to just the most useful information.
; ******************************************************************************
:Step9
RUN PGM=HWYNET
  FILEI LINKI = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.detailed.net,
    EXCLUDE   = AM_DAGP, AM_SRGP, AM_HOV, AM_DAtol, AM_SRtol, 
    EXCLUDE   = MD_DAGP, MD_SRGP, MD_HOV, MD_DAtol, MD_SRtol, MD_1000, MD_VOL2WY,
    EXCLUDE   = PM_DAGP, PM_SRGP, PM_HOV, PM_DAtol, PM_SRtol, 
    EXCLUDE   = EV_DAGP, EV_SRGP, EV_HOV, EV_DAtol, EV_SRtol, EV_1000, EV_VOL2WY,
    EXCLUDE   = DY_DAGP, DY_SRGP, DY_HOV, DY_DAtol, DY_SRtol

  FILEO NETO = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.net	
ENDRUN

:EndAssign
ENDLOOP
:endofloop


if (networkyear > 2000)  ;90's nets had no HOV, which will crash this
;goto :StepJoin
; ******************************************************************************
; Purpose:  Transfer data on HOV links to their companion mainline links.  Save
; several kinds of networks: 1) HOV only, 2) Fwy only, 3) Everything but HOV with
; data transfered.
; ******************************************************************************
:StepHOV
RUN PGM=HWYNET
  FILEI LINKI = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.net	
  FILEO NETO = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.HOVonlyTMP.net	
  
  ARRAY _N=20000
  ARRAY _X=20000
  ARRAY _Y=20000

  phase=input filei=ni.1
    _index = _index + 1
    _N[_index] = N
    _X[_index] = X
    _Y[_index] = Y
  endphase
  

  PHASE = LINKMERGE
    if (!(FT == 34,39))  ;delete anything that's not HOV
      delete
    else
      LOOP _ind = 1,_index  ;links do not have XY naturally, so add it in
        if (li.1.A = _N[_ind])
          AX = _X[_ind]
          AY = _Y[_ind]
        endif
        if (li.1.B = _N[_ind])
          BX = _X[_ind]
          BY = _Y[_ind]
        endif    
      ENDLOOP
    endif    
  ENDPHASE
ENDRUN

; ******************************************************************************
; Purpose:  HOV only
; ******************************************************************************
RUN PGM=HWYNET
  FILEI LINKI = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.HOVonlyTMP.net	
  FILEO NETO  = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.HOVonly.net	
 
  ARRAY _LA = 20000
  ARRAY _LB = 20000
  ARRAY _VectorQuad = 20000
  
  phase=input filei=li.1
   _index = _index + 1
   _LA[_index] = A
   _LB[_index] = B
   _Xdif = BX - AX
   _Ydif = BY - AY
   
   ;To match HOV and mainline companions, it is necessary to 
   ;identify that each link is generally aimed in the same direction (ID 8 directions)
   if     (_Xdif >= 0 && _Ydif >  0)  
     if (_Ydif <  _Xdif)   _VectorQuad[_index] = 1
     if (_Ydif >= _Xdif)   _VectorQuad[_index] = 2
   elseif (_Xdif <  0 && _Ydif >  0)
     if (-_Ydif <  _Xdif)   _VectorQuad[_index] = 3
     if (-_Ydif >= _Xdif)   _VectorQuad[_index] = 4
   elseif (_Xdif <  0 && _Ydif <= 0)
     if (-_Ydif <  -_Xdif)   _VectorQuad[_index] = 5
     if (-_Ydif >= -_Xdif)   _VectorQuad[_index] = 6
   elseif (_Xdif >  0 && _Ydif <  0)
     if (_Ydif <  -_Xdif)   _VectorQuad[_index] = 7
     if (_Ydif >= -_Xdif)   _VectorQuad[_index] = 8
   endif
  endphase
  PHASE = LINKMERGE
      LOOP _ind = 1,_index
        if (li.1.A = _LA[_ind] && li.1.B = _LB[_ind])
          VectorQuad = _VectorQuad[_ind]
        endif
      ENDLOOP
  ENDPHASE
ENDRUN

; ******************************************************************************
; Purpose:  Add AX, etc to link data
; ******************************************************************************
:StepFWY
RUN PGM=HWYNET
  FILEI LINKI = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.net	
  FILEO NETO  = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.FwyOnlyTMP.net	
  
  ARRAY _N=20000
  ARRAY _X=20000
  ARRAY _Y=20000

  phase=input filei=ni.1
    _index = _index + 1
    _N[_index] = N
    _X[_index] = X
    _Y[_index] = Y
  endphase
  

  PHASE = LINKMERGE
    if (!(FT == 29-33,35-37))  ;Delete anything that's not part of the main freeway system (even HOV)
      delete
    else
      LOOP _ind = 1,_index  ;links do not have XY naturally, so add it in
        if (li.1.A = _N[_ind])
          AX = _X[_ind]
          AY = _Y[_ind]
        endif
        if (li.1.B = _N[_ind])
          BX = _X[_ind]
          BY = _Y[_ind]
        endif    
      ENDLOOP
    endif    
  ENDPHASE
ENDRUN

; ******************************************************************************
; Purpose:  Fwy only
; ******************************************************************************
RUN PGM=HWYNET
  FILEI LINKI = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.FwyOnlyTMP.net		
  FILEO NETO  = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.FWYonly.net	
 
  ARRAY _LA = 20000
  ARRAY _LB = 20000
  ARRAY _VectorQuad = 20000
  
  phase=input filei=li.1
   _index = _index + 1
   _LA[_index] = A
   _LB[_index] = B
   _Xdif = BX - AX
   _Ydif = BY - AY
   
   ;To match HOV and mainline companions, it is necessary to 
   ;identify that each link is generally aimed in the same direction (ID 8 directions)
  if (ft = 31-32,35)
   if     (_Xdif >= 0 && _Ydif >  0)
     if (_Ydif <  _Xdif)   _VectorQuad[_index] = 1
     if (_Ydif >= _Xdif)   _VectorQuad[_index] = 2
   elseif (_Xdif <  0 && _Ydif >  0)
     if (-_Ydif <  _Xdif)   _VectorQuad[_index] = 3
     if (-_Ydif >= _Xdif)   _VectorQuad[_index] = 4
   elseif (_Xdif <  0 && _Ydif <= 0)
     if (-_Ydif <  -_Xdif)   _VectorQuad[_index] = 5
     if (-_Ydif >= -_Xdif)   _VectorQuad[_index] = 6
   elseif (_Xdif >  0 && _Ydif <  0)
     if (_Ydif <  -_Xdif)   _VectorQuad[_index] = 7
     if (_Ydif >= -_Xdif)   _VectorQuad[_index] = 8
   endif
  endif
  endphase
  PHASE = LINKMERGE
    if (ft = 31-32,35)
      LOOP _ind = 1,_index
        if (li.1.A = _LA[_ind] && li.1.B = _LB[_ind])
          VectorQuad = _VectorQuad[_ind]
        endif
      ENDLOOP
    endif
  ENDPHASE
ENDRUN


; ******************************************************************************
; Purpose:  Merge the HOV data over to the companion fwy link
; ******************************************************************************
:StepJoin
RUN PGM=HWYNET
  FILEI NETI[1] = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.FWYonly.net	
  FILEI NETI[2] = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.HOVonly.net	
  FILEO NETO    = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.HOVFWYjoinedTMP.net	

  ARRAY _A=10000
  ARRAY _B=10000
  ARRAY _AX=10000
  ARRAY _BX=10000
  ARRAY _AY=10000
  ARRAY _BY=10000
  ARRAY _VectorQuadHOV=10000
  
  ARRAY _AMVOL=10000
  ARRAY _MDVOL=10000
  ARRAY _PMVOL=10000
  ARRAY _EVVOL=10000
  ARRAY _DYVOL=10000
  ARRAY _AM_VC=10000
  ARRAY _PM_VC=10000

  phase=input filei=li.2
   _LCount=_LCount+1
   _A[_LCount]=A
   _B[_LCount]=B
   _AX[_LCount]=AX
   _AY[_LCount]=AY
   _BX[_LCount]=BX
   _BY[_LCount]=BY
   _AMVOL[_LCount]=AM_VOL
   _MDVOL[_LCount]=MD_VOL
   _PMVOL[_LCount]=PM_VOL
   _EVVOL[_LCount]=EV_VOL
   _DYVOL[_LCount]=DY_VOL
   _AM_VC[_LCount]=AM_VC
   _PM_VC[_LCount]=PM_VC
   _VectorQuadHOV[_LCount] = VectorQuad

  endphase
  
  PHASE = LINKMERGE
    if (li.1.ft = 31,32,35)
      LOOP _ind = 1,_LCount

        ;determine the hypotenues distance between the A of the mainline and A of the HOV link
        _AXmeter = _AX[_ind] - LI.1.AX
        _AYmeter = _AY[_ind] - LI.1.AY
        _AhypotMeter = sqrt(pow(_AXmeter,2) + pow(_AYmeter,2))
        _AhypotMiles = _AhypotMeter / 1609.344  ;miles = meters / meters per mile

        ;determine the hypotenues distance between the B of the mainline and B of the HOV link
        _BXmeter = _BX[_ind] - LI.1.BX
        _BYmeter = _BY[_ind] - LI.1.BY
        _BhypotMeter = sqrt(pow(_BXmeter,2) + pow(_BYmeter,2))
        _BhypotMiles = _BhypotMeter / 1609.344  ;miles = meters / meters per mile
        
        ;if links are close and aimed in the same direction, then they can be considered matches.
        ;Some links barely fall into different vector bins, (either horiz., vert., or y=x), so
        ;Check rise over run, if small, must be parallel
        _XdifF = (LI.1.AX - LI.1.BX)
        _YdifF = (LI.1.AY - LI.1.BY)
        if (_YdifF<>0) _XYratF= _XdifF / _YdifF
        if (_XdifF<>0) _YXratF= _YdifF / _XdifF

        
        _XdifH = (_AX[_ind] - _BX[_ind])
        _YdifH = (_AY[_ind] - _BY[_ind])
        if (_YdifH<>0) _XYratH= _XdifH / _YdifH
        if (_XdifH<>0) _YXratH= _YdifH / _XdifH
        
        _flagParallel = 0
        if ((_XYratF <= .02) && (_XYratH <= .02))         _flagParallel = 1
        if ((_YXratF <= .02) && (_YXratH <= .02))         _flagParallel = 1
        
        _tmp = abs( _XYratF - _XYratH)
      ;  _AYdif = abs(_AY[_ind] - LI.1.AY)
      ;  _BXdif = abs(_BX[_ind] - LI.1.BX)
      ;  _BYdif = abs(_BY[_ind] - LI.1.BY)

        /*
          if (LI.1.A = 11338)
            print csv=t, file=tmp1.csv, APPEND=F  form=12.2 list= 
              LI.1.A, LI.1.B, _A[_ind],_B[_ind], 
            _AhypotMiles, _BhypotMiles, li.1.VectorQuad, _VectorQuadHOV[_ind], 
            LI.1.AX, LI.1.BX, _XdifF,
            LI.1.AY, LI.1.BY, _YdifF, _XYratF,
            _AX[_ind], _BX[_ind], _XdifH, 
            _AY[_ind], _BY[_ind], _YdifH, _XYratH, _tmp
          endif
        if ((_AhypotMiles < 2) && (_BhypotMiles < 2))
          _flag = 0
          if (_tmp < .5)
            _flag = 1
          elseif (li.1.VectorQuad = _VectorQuadHOV[_ind])
            _flag = 1
          endif
          if (_flag = 1)
            print csv=t, file=tmp1.csv, APPEND=F  form=12.2 list= 
              LI.1.A, LI.1.B, _A[_ind],_B[_ind], 
            _AhypotMiles, _BhypotMiles, li.1.VectorQuad, _VectorQuadHOV[_ind], 
            LI.1.AX, LI.1.BX, _XdifF,
            LI.1.AY, LI.1.BY, _YdifF, _XYratF,
            _AX[_ind], _BX[_ind], _XdifH, 
            _AY[_ind], _BY[_ind], _YdifH, _XYratH, _tmp
          endif
        endif
*/
       
        if ((_AhypotMiles < .25) && (_BhypotMiles < .25))  ;if A and B of both links are close to each other
          _flag = 0
          if (_tmp < .10)  ;if the ratio of slopes is similar
            _flag = 1
          elseif (li.1.VectorQuad = _VectorQuadHOV[_ind])  ;if they're in the same general direction
            _flag = 1
          elseif (_flagParallel = 1)  ;if they are either vertical or horizontal
            _flag = 1
          endif

          if (_flag = 1)  ; if they passed, write the data from the managed lane to its companion.
       ;     print csv=t, file=tmp2.csv, APPEND=F  form=12.2 list= LI.1.A, LI.1.B, _A[_ind],_B[_ind], _ind, _AhypotMiles, _BhypotMiles, li.1.VectorQuad, _VectorQuadHOV[_ind],  _XYratF, _XYratH, _tmp

            /* debugging print
            print csv=t, file=tmp2.csv, APPEND=F  form=12.2 list= 
              LI.1.A, LI.1.B, _A[_ind],_B[_ind], 
            _AhypotMiles, _BhypotMiles, li.1.VectorQuad, _VectorQuadHOV[_ind], 
            LI.1.AX, LI.1.BX, _XdifF,
            LI.1.AY, LI.1.BY, _YdifF, _XYratF,
            _AX[_ind], _BX[_ind], _XdifH, 
            _AY[_ind], _BY[_ind], _YdifH, _XYratH, _tmp  */

            MNGA = _A[_ind]
            MNGB = _B[_ind]
            AM_MNG = _AMVOL[_ind]
            MD_MNG = _MDVOL[_ind]
            PM_MNG = _PMVOL[_ind]
            EV_MNG = _EVVOL[_ind]
            DY_MNG = _DYVOL[_ind]
            AM_VC_MNG = _AM_VC[_ind]
            PM_VC_MNG = _PM_VC[_ind]
          endif
        endif
      ENDLOOP
    endif ;if fwy links
  
  ENDPHASE
ENDRUN


; ******************************************************************************
; Purpose:  Upon review of the HOVFWYjoinedTMP net, and confirmed to work properly,
; remove the HOV links and update the main volume fields.
; ******************************************************************************
RUN PGM=HWYNET
  FILEI NETI[1] = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.detailed.net		
  FILEI NETI[2] = @ParentDir@@TempDir@@ATmp@@unloadednetprefix@_4pd.@AssignType@.HOVFWYjoinedTMP.net		
  FILEO NETO    = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.MNGremoved.net, EXCLUDE=Vectorquad, MngA, MngB	
  
  MERGE RECORD = F
  
  PHASE = LINKMERGE
    if (li.1.ft = 34,38,39)  
      delete
    else
      AM_VOL = li.1.AM_VOL + li.2.AM_MNG
      MD_VOL = li.1.MD_VOL + li.2.MD_MNG
      PM_VOL = li.1.PM_VOL + li.2.PM_MNG
      EV_VOL = li.1.EV_VOL + li.2.EV_MNG
      DY_VOL = li.1.DY_VOL + li.2.DY_MNG
  
      AM_MNG = li.2.AM_MNG
      MD_MNG = li.2.MD_MNG
      PM_MNG = li.2.PM_MNG
      EV_MNG = li.2.EV_MNG
      DY_MNG = li.2.DY_MNG
      ;Compute capture rate (those who used HOV lanes as a share of those eligible - note: doesn't apply when TOL is the option because "eligible" is everyone)
      if (li.2.AM_MNG > 0) AM_HOVPCTE = round((li.2.AM_MNG / (li.2.AM_MNG + li.1.AM_SRGP))*100)/100
      if (li.2.PM_MNG > 0) PM_HOVPCTE = round((li.2.PM_MNG / (li.2.PM_MNG + li.1.PM_SRGP))*100)/100

      AM_VC_MNG = li.2.AM_VC_MNG
      PM_VC_MNG = li.2.PM_VC_MNG
    endif
  ENDPHASE
ENDRUN
endif ;networkyear > 2000


;**************************************************************************
;Purpose:	Final auto skims
;**************************************************************************
RUN PGM=HWYLOAD  
ZONES=@UsedZones@
ZONEMSG = @ZoneMsgRate@  ;reduces print messages in TPP DOS. (i.e. runs faster).

FILEI  NETI    = @ParentDir@@ADir@@Ao@@unloadednetprefix@_4pd.@AssignType@.net	
      ZDATI[1] = @ParentDir@@IDir@@Io@Urbanization.DBF  ;termtime, square miles

FILEO  MATO[1] = @ParentDir@@ADir@@Ao@@Ao_Skim@skm_autotime.mtx, mo=2,1,3,5 name = DISTANCE, TIME_SFF, TIME_AM, TIME_PM

PHASE=LINKREAD
    _DIST = LI.DISTANCE - LI.DISTEXCEPT   ;Long external links should not be included in distrib because it affects IXXI trip lengths.
    LW.BASE_TIME = (_DIST/LI.SFF)*60 
    LW.TPKAM     = (_DIST/LI.AM_SPD)*60 
    LW.TPKPM     = (_DIST/LI.PM_SPD)*60 
ENDPHASE

PHASE=ILOOP
   PATHLOAD CONSOLIDATE=T, PATH=LW.BASE_TIME,
            EXCLUDEJ=@dummyzones@,  ; exclude "dummy" zones
            mw[1]=PATHCOST, NOACCESS=0,  ; zone-to-zone times (no access = 10000)
            mw[2]=PATHTRACE(LI.DISTANCE), NOACCESS=0.0 ; zone-to-zone distances (no access = 0.0)

   PATHLOAD CONSOLIDATE=T, PATH=LW.TPKAM,
            EXCLUDEJ=@dummyzones@,  ; exclude "dummy" zones
            mw[3]=PATHCOST, NOACCESS=0  ; zone-to-zone times (no access = 10000)

   PATHLOAD CONSOLIDATE=T, PATH=LW.TPKPM,
            EXCLUDEJ=@dummyzones@,  ; exclude "dummy" zones
            mw[5]=PATHCOST, NOACCESS=0  ; zone-to-zone times (no access = 10000)

;  add intrazonal times and distances to interzonal cells (assume intrazonal speed is 20mph)
   mw[2][i]= 0.5*((ZI.1.SQMILE[i])^0.5)  ;half square root of square miles = average distance (in miles)
   mw[4][i]= 0.5*((ZI.1.SQMILE[i])^0.5)
   mw[6][i]= 0.5*((ZI.1.SQMILE[i])^0.5)
   
   mw[1][i]= (mw[2][i]/20)*60
   mw[3][i]= (mw[4][i]/20)*60
   mw[5][i]= (mw[6][i]/20)*60

   if (mw[2][i] = 0) ;Having dist=0 can cause divide by 0 errors in unused zone fields.
     mw[2][i] = 1
   endif

;  add origin and destination terminal times to all zones
   mw[1]=mw[1]+ZI.1.TERMTIME[j]
   mw[3]=mw[3]+ZI.1.TERMTIME[j]
   mw[5]=mw[5]+ZI.1.TERMTIME[j]

  jloop
    if (mw[2] = 0 && i >=1) mw[2] = 1 ;Having dist=0 can cause divide by 0 errors in unused zone fields.
  endjloop
ENDPHASE
ENDRUN

if (runselectlink == 1)

 RUN PGM=MATRIX

   FILEI MATI[1] = @ParentDir@@TempDir@@Atmp@SelectLink_AM.mtx
         MATI[2] = @ParentDir@@TempDir@@Atmp@SelectLink_MD.mtx
         MATI[3] = @ParentDir@@TempDir@@Atmp@SelectLink_PM.mtx
         MATI[4] = @ParentDir@@TempDir@@Atmp@SelectLink_EV.mtx

   FILEO MATO[2] = @ParentDir@@TempDir@@Atmp@SelectLink_link.mtx, MO=1-5, NAME=AM, MD, PM, EV, ALL
   ZONEMSG       = @ZoneMsgRate@                                ;reduces print messages in TPP DOS. (i.e. runs faster).


   MW[1]=MI.1.DA_NON+MI.1.SR_NON+MI.1.SR_HOV+MI.1.DA_TOL+MI.1.SR_TOL
   MW[2]=MI.2.DA_NON+MI.2.SR_NON+MI.2.SR_HOV+MI.2.DA_TOL+MI.2.SR_TOL
   MW[3]=MI.3.DA_NON+MI.3.SR_NON+MI.3.SR_HOV+MI.3.DA_TOL+MI.3.SR_TOL
   MW[4]=MI.4.DA_NON+MI.4.SR_NON+MI.4.SR_HOV+MI.4.DA_TOL+MI.4.SR_TOL
   MW[5]=mw[1]+mw[2]+mw[3]+mw[4]

  JLOOP    ;It will put zero-value cells in the wrong place, so force "no zero-values"
     if (mw[1][j] == 0) mw[1][j] = .00000001
     if (mw[2][j] == 0) mw[2][j] = .00000001
     if (mw[3][j] == 0) mw[3][j] = .00000001
     if (mw[4][j] == 0) mw[4][j] = .00000001
     if (mw[5][j] == 0) mw[5][j] = .00000001
   ENDJLOOP


;@SelLinkReduceToDistricts@  renumber file=@Zone2DistrictFile@, missingzi=m, missingzo=w
 ENDRUN

endif

:end



;Calculate Elapsed Time (options: /s=seconds, /n=minutes, /h=hours)
	*(..\..\_ElapsedTime\ElapsedTime.exe   _timchk2.txt /n  >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO Above is time to run 4AssignHwy_ManagedLanes.s >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO --------------------------------- >> ..\..\_Log\_ElapsedTimeReport.txt)
	
	*(..\..\_ElapsedTime\ElapsedTime.exe   _timchk1.txt /n  >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO Above is time to run FINAL ASSIGNMENT >> @ParentDir@_Log\_ElapsedTimeReport.txt)
	*(ECHO ================================================== >> ..\..\_Log\_ElapsedTimeReport.txt)
	
	*(ECHO . >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO . >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO ************************************************** >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(..\..\_ElapsedTime\ElapsedTime.exe   _IP_chk.txt /n  >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO Above is time to run WFRC-MAG MODEL in MINUTES>> @ParentDir@_Log\_ElapsedTimeReport.txt)
	*(ECHO . >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO or >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(..\..\_ElapsedTime\ElapsedTime.exe   _IP_chk.txt /h  >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO Above is time to run WFRC-MAG MODEL in WHOLE HOURS>> @ParentDir@_Log\_ElapsedTimeReport.txt)
	*(ECHO . >> ..\..\_Log\_ElapsedTimeReport.txt)
	*(ECHO ************************************************** >> ..\..\_Log\_ElapsedTimeReport.txt)
	


*(DEL 9FinlAsn.txt) 
*(copy *.prn .\out\4AssignHwy_ManagedLanes.out)
*(del 4AssignHwy_ManagedLanes.txt)
*(del TPPL*)
