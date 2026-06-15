//+------------------------------------------------------------------+
//|                                      SMC_Structure_Core.mq5      |
//|  Smart Money Concepts - Core Structure Engine                    |
//|  Converted from LuxAlgo "Smart Money Concepts" Pine Script logic |
//|                                                                  |
//|  PHASE 1 CORE - implements:                                      |
//|    - Swing pivot detection                                       |
//|    - Internal pivot detection (length = 5)                       |
//|    - BOS / IDM / CHoCH(swing) / MSS(internal) / CBOS / TBOS     |
//|      / Trap sequence logic                                       |
//|    - Post-CBOS IDM horizontal level (extend right until broken)  |
//|    - HH/HL/LH/LL swing point labels                              |
//|    - Strong/Weak High & Low trailing lines                       |
//|    - 8 hidden buffers exposing every BOS/CHoCH event for an EA  |
//|                                                                  |
//|  PHASE 2 ADD-ON - Order Block / Breaker Block module:            |
//|    - OB detected from the candle that caused the displacement    |
//|      behind every confirmed BOS / CBOS(MSS) (rules 2,3)          |
//|    - Bullish OB (demand) / Bearish OB (supply) classification    |
//|    - Trend confirmed only after BOS + MSS in same direction      |
//|    - Only trend-aligned OBs are drawn; counter-trend hidden      |
//|    - Counter-trend OBs auto-convert to Breaker Blocks only after |
//|      a confirmed BOS breaks through them (rules 4,5,9)           |
//|    - Active zones extend right until mitigated (rules 6,7)       |
//|    - All zones tracked in g_obBoxes[] (rule 10)                  |
//|    - Self-contained: see "ORDER BLOCK / BREAKER BLOCK MODULE"    |
//+------------------------------------------------------------------+
#property copyright "Converted for personal/internal use"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

//--- hidden EA-readable signal buffers
#property indicator_label1  "SwingBullBOS"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "SwingBullCHoCH"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "SwingBearBOS"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "SwingBearCHoCH"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "IntBullBOS"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "IntBullCHoCH"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "IntBearBOS"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "IntBearCHoCH"
#property indicator_type8   DRAW_NONE

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Swing Structure ==="
input int    InpSwingLength          = 50;
input bool   InpShowSwingStructure   = true;
input bool   InpShowSwingLabels      = false;

input group "=== Internal Structure ==="
input int    InpInternalLength       = 5;
input bool   InpShowInternalStructure = true;

input group "=== Strong / Weak High Low ==="
input bool   InpShowStrongWeak       = true;

input group "=== Label Colors ==="
input color  InpColorBOS             = C'8,153,129';    // BOS (bull green)
input color  InpColorBearBOS         = C'242,54,69';    // BOS (bear red)
input color  InpColorIDM             = C'180,180,60';   // IDM - yellow
input color  InpColorCHoCH           = C'255,140,0';    // CHoCH / MSS - orange
input color  InpColorCBOS            = C'100,200,255';  // CBOS - light blue
input color  InpColorTrap            = C'200,80,200';   // Trap - purple
input color  InpColorTBOS            = C'255,80,80';    // TBOS - bright red
input color  InpColorIDMLevel        = C'180,180,60';   // Post-CBOS IDM horizontal line

input group "=== Appearance ==="
input int    InpStructureLabelFontSize = 8;
input int    InpSwingPointFontSize     = 7;

input group "=== Performance ==="
input int    InpMaxHistoryBars       = 0;

//--- which trend bias the OB/BB module treats as "the current market trend"
enum ENUM_OB_TREND_SOURCE
  {
   OB_TREND_SWING    = 0,   // use swing-structure trend bias
   OB_TREND_INTERNAL = 1    // use internal-structure trend bias
  };

input group "=== Order Blocks & Breaker Blocks ==="
input bool   InpShowOrderBlocks      = true;     // show Order Block zones
input bool   InpShowBreakerBlocks    = true;     // show Breaker Block zones
input bool   InpOB_UseSwingBreaks    = true;     // detect OBs from swing BOS/CHoCH
input bool   InpOB_UseInternalBreaks = true;     // detect OBs from internal BOS/MSS
input int    InpOB_MaxLookback       = 30;       // max bars to search back for the OB candle
input int    InpOB_MaxActiveZones    = 50;       // max OB/BB zones kept on chart
input bool   InpOB_MitigateByWick    = false;    // true = wick touch mitigates, false = candle close
input bool   InpOB_ShowLabels        = true;     // show "Bull/Bear OB / BB" labels
input ENUM_OB_TREND_SOURCE InpOB_TrendSource = OB_TREND_SWING; // trend used for rules 1, 4 & 5
input color  InpColorBullOB          = C'20,130,130';   // Bullish Order Block (demand)
input color  InpColorBearOB          = C'130,60,150';   // Bearish Order Block (supply)
input color  InpColorBullBB          = C'60,180,75';    // Bullish Breaker Block
input color  InpColorBearBB          = C'200,60,60';    // Bearish Breaker Block

input group "=== Premium / Discount Array ==="
input bool   InpShowPDArray          = true;     // show Premium/Discount array levels
input double InpPDRetracement        = 0.60;     // retracement % (0.60 = 60%)
input int    InpSLBufferPoints       = 10;       // SL buffer in points
input color  InpColorPremium         = C'255,180,180'; // premium zone color
input color  InpColorDiscount        = C'180,220,180'; // discount zone color
input color  InpColorPDLine          = C'100,100,100'; // PD level line color

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define LEG_BULLISH     1
#define LEG_BEARISH     0
#define TREND_NONE      0
#define TREND_BULLISH   1
#define TREND_BEARISH  -1

// Sequence states
#define SEQ_NONE        0   // no pending IDM
#define SEQ_IDM_BULL    1   // bullish IDM placed (opposite to bearish bias), awaiting confirm
#define SEQ_IDM_BEAR    2   // bearish IDM placed (opposite to bullish bias), awaiting confirm

//+------------------------------------------------------------------+
//| Data structures                                                  |
//+------------------------------------------------------------------+
struct PivotPoint
  {
   double   price;
   double   lastPrice;
   datetime time;
   int      barIndex;
   bool     crossed;
   bool     valid;
  };

struct TrailingExtremes
  {
   double   top;
   double   bottom;
   datetime lastTopTime;
   datetime lastBottomTime;
   bool     valid;
  };

// Tracks a pending IDM event waiting for confirmation
struct PendingIDM
  {
   bool     active;
   bool     isBullish;       // true = bullish IDM (breaks up, against bearish trend)
   double   price;           // price level of the IDM break
   datetime time;            // bar time of IDM break bar
   int      barIndex;        // bar index of IDM break bar
   double   pivotPrice;      // the pivot that was broken
   datetime pivotTime;       // time of that pivot
   int      pivotBarIndex;   // bar index of that pivot
   string   objPrefix;       // object name prefix for the IDM line/label
  };

// Tracks a post-CBOS IDM horizontal level
struct IDMLevel
  {
   bool     active;
   bool     isBullish;       // direction of CBOS that created this level
   double   price;           // the IDM level price
   datetime startTime;       // start bar of the level
   bool     broken;          // has price closed through it?
   string   lineName;        // chart object name for the line
   string   lblName;         // chart object name for the label
  };

// A single Order Block / Breaker Block zone (OB & BB module)
struct OBBox
  {
   bool     active;     // still being tracked (false once mitigated)
   bool     mitigated;  // price has returned into the zone (rule 7)
   bool     isBullish;  // true = bullish zone (demand), false = bearish zone (supply)
   bool     isBreaker;  // false = Order Block, true = Breaker Block (rule 9)
   bool     internal;   // created from an internal-structure break (vs swing)
   double   top;        // OB candle high
   double   bottom;     // OB candle low
   datetime time1;      // OB candle time (left edge of the zone)
   datetime time2;      // current right edge (extends while active, rule 6)
   int      obBarIndex; // bar index of the OB candle (de-duplication)
   string   boxName;    // chart object name of the rectangle
   string   lblName;    // chart object name of the text label
  };

//+------------------------------------------------------------------+
//| Global state                                                     |
//+------------------------------------------------------------------+
PivotPoint  swingHigh, swingLow, internalHigh, internalLow;
TrailingExtremes trailing;

int swingLeg     = -1;
int internalLeg  = -1;

int swingTrendBias    = TREND_NONE;
int internalTrendBias = TREND_NONE;

bool swingTrendConfirmed    = false;
bool internalTrendConfirmed = false;

// Sequence state machines
int         swingSeqState    = SEQ_NONE;
PendingIDM  swingPendingIDM;
IDMLevel    swingIDMLevel;

int         intSeqState      = SEQ_NONE;
PendingIDM  intPendingIDM;
IDMLevel    intIDMLevel;

// Order Block / Breaker Block module storage (rule 10)
OBBox g_obBoxes[];
int   g_obCount = 0;

//--- indicator buffers
double BufSwingBullBOS[];
double BufSwingBullCHoCH[];
double BufSwingBearBOS[];
double BufSwingBearCHoCH[];
double BufIntBullBOS[];
double BufIntBullCHoCH[];
double BufIntBearBOS[];
double BufIntBearCHoCH[];

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufSwingBullBOS,   INDICATOR_DATA);
   SetIndexBuffer(1, BufSwingBullCHoCH, INDICATOR_DATA);
   SetIndexBuffer(2, BufSwingBearBOS,   INDICATOR_DATA);
   SetIndexBuffer(3, BufSwingBearCHoCH, INDICATOR_DATA);
   SetIndexBuffer(4, BufIntBullBOS,     INDICATOR_DATA);
   SetIndexBuffer(5, BufIntBullCHoCH,   INDICATOR_DATA);
   SetIndexBuffer(6, BufIntBearBOS,     INDICATOR_DATA);
   SetIndexBuffer(7, BufIntBearCHoCH,   INDICATOR_DATA);

   ArraySetAsSeries(BufSwingBullBOS,   false);
   ArraySetAsSeries(BufSwingBullCHoCH, false);
   ArraySetAsSeries(BufSwingBearBOS,   false);
   ArraySetAsSeries(BufSwingBearCHoCH, false);
   ArraySetAsSeries(BufIntBullBOS,     false);
   ArraySetAsSeries(BufIntBullCHoCH,   false);
   ArraySetAsSeries(BufIntBearBOS,     false);
   ArraySetAsSeries(BufIntBearCHoCH,   false);

   for(int b = 0; b < 8; b++)
      PlotIndexSetDouble(b, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC Structure Core");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SMC_");
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double Highest(const double &arr[], int from, int to)
  {
   double m = arr[from];
   for(int k = from+1; k <= to; k++)
      if(arr[k] > m) m = arr[k];
   return m;
  }

double Lowest(const double &arr[], int from, int to)
  {
   double m = arr[from];
   for(int k = from+1; k <= to; k++)
      if(arr[k] < m) m = arr[k];
   return m;
  }

//+------------------------------------------------------------------+
//| ORDER BLOCK / BREAKER BLOCK MODULE                               |
//|                                                                  |
//| Self-contained, additive module.                                |
//|                                                                  |
//|   DetectOrderBlockOnBreak()       - rules 2,3       (creation)  |
//|   CheckBreakerConversionOnBOS()   - rules 4,5,9     (BB on BOS) |
//|   UpdateOrderBlocksAndBreakers()  - rules 6,7,10    (lifecycle)  |
//|                                                                  |
//| TREND RULES:                                                     |
//|   - Trend is ONLY confirmed after BOS + MSS in same direction    |
//|   - Before confirmation: OBs are stored but NEVER drawn          |
//|   - After confirmation: only trend-aligned OBs are drawn         |
//|   - Counter-trend OBs are hidden; they await BOS → BB conversion|
//|                                                                  |
//| BREAKER BLOCK RULES:                                             |
//|   - A counter-trend OB becomes a Breaker Block only when a       |
//|     confirmed BOS follows the price breaking through the OB      |
//|   - BB conversion happens in CheckBreakerConversionOnBOS(),     |
//|     called from CheckStructureBreaks() on every BOS event        |
//|   - No auto-conversion on the bar loop; BOS is mandatory         |
//|                                                                  |
//| All zones stored in g_obBoxes[] (rule 10).                       |
//+------------------------------------------------------------------+

//--- "current market trend" used by this module (rule 1)
//--- Returns TREND_NONE if trend is not yet confirmed by BOS+MSS sequence
int OB_CurrentTrend()
  {
   int bias = (InpOB_TrendSource == OB_TREND_INTERNAL) ? internalTrendBias : swingTrendBias;
   bool confirmed = (InpOB_TrendSource == OB_TREND_INTERNAL) ? internalTrendConfirmed : swingTrendConfirmed;
   return confirmed ? bias : TREND_NONE;
  }

//--- scan backwards from breakIdx to searchFrom for the last candle whose
//--- colour is OPPOSITE to the displacement that caused the break (rule 3):
//---   displacementBullish == true  -> look for the last BEARISH candle
//---   displacementBullish == false -> look for the last BULLISH  candle
int FindOppositeCandle(int breakIdx, int searchFrom, bool displacementBullish,
                        const double &open[], const double &close[])
  {
   for(int k = breakIdx; k >= searchFrom; k--)
     {
      bool isBearCandle = close[k] < open[k];
      bool isBullCandle = close[k] > open[k];
      if(displacementBullish  && isBearCandle) return k;
      if(!displacementBullish && isBullCandle) return k;
     }
   return -1;
  }

//--- delete the chart objects belonging to one zone
void OB_DeleteObjects(OBBox &b)
  {
   if(ObjectFind(0, b.boxName) >= 0) ObjectDelete(0, b.boxName);
   if(ObjectFind(0, b.lblName) >= 0) ObjectDelete(0, b.lblName);
  }

//--- drop the oldest tracked zone once InpOB_MaxActiveZones is exceeded
void OB_RemoveOldest()
  {
   if(g_obCount <= 0) return;
   OB_DeleteObjects(g_obBoxes[0]);
   for(int n = 0; n < g_obCount-1; n++)
      g_obBoxes[n] = g_obBoxes[n+1];
   g_obCount--;
   ArrayResize(g_obBoxes, g_obCount);
  }

//--- wipe every tracked zone (used on a full indicator recalculation)
void OB_ResetAll()
  {
   for(int n = 0; n < g_obCount; n++)
      OB_DeleteObjects(g_obBoxes[n]);
   g_obCount = 0;
   ArrayResize(g_obBoxes, 0);
  }

//--- register a brand-new Order Block zone from the candle at obBarIdx
//--- (rules 3, 4, 8, 9 - it starts life as an Order Block, never a Breaker)
void OB_Register(int obBarIdx, bool isBullish, bool internalFlag,
                  const datetime &time[], const double &high[], const double &low[])
  {
   // de-duplicate: this candle/timeframe combo may already be tracked
   for(int n = 0; n < g_obCount; n++)
     {
      if(g_obBoxes[n].active && g_obBoxes[n].obBarIndex == obBarIdx && g_obBoxes[n].internal == internalFlag)
         return;
     }

   OBBox b;
   b.active     = true;
   b.mitigated  = false;
   b.isBullish  = isBullish;
   b.isBreaker  = false;          // always starts as an Order Block (rule 9)
   b.internal   = internalFlag;
   b.top        = high[obBarIdx];
   b.bottom     = low[obBarIdx];
   b.time1      = time[obBarIdx];
   b.time2      = time[obBarIdx];
   b.obBarIndex = obBarIdx;

   string pfx = internalFlag ? "SMC_INT_OB" : "SMC_SWING_OB";
   string uid = IntegerToString((long)time[obBarIdx]) + "_" + IntegerToString(obBarIdx);
   b.boxName  = pfx + "_BOX_" + uid;
   b.lblName  = pfx + "_LBL_" + uid;

   int n = g_obCount;
   ArrayResize(g_obBoxes, n+1);
   g_obBoxes[n] = b;
   g_obCount++;

   if(g_obCount > InpOB_MaxActiveZones)
      OB_RemoveOldest();
  }

//+------------------------------------------------------------------+
//| Entry point #1 - Order Block detection (rules 2, 3, 4)           |
//|                                                                  |
//| Called from CheckStructureBreaks() on every confirmed BOS and    |
//| CBOS/MSS event (both directions). It locates the order block      |
//| that caused the displacement leading to that break:               |
//|   displacementBullish = true  -> last bearish candle -> Bull OB  |
//|   displacementBullish = false -> last bullish candle -> Bear OB  |
//|                                                                  |
//| Whether the new OB counts as a "valid continuation OB" (rule 4)  |
//| or a counter-trend OB is decided continuously afterwards by      |
//| UpdateOrderBlocksAndBreakers(), since trendBias can keep moving. |
//+------------------------------------------------------------------+
void DetectOrderBlockOnBreak(int breakIdx, int pivotBarIdx, bool displacementBullish, bool internalFlag,
                              const datetime &time[], const double &open[], const double &high[],
                              const double &low[], const double &close[])
  {
   if(!InpShowOrderBlocks && !InpShowBreakerBlocks) return;
   if(internalFlag  && !InpOB_UseInternalBreaks) return;
   if(!internalFlag && !InpOB_UseSwingBreaks)     return;
   if(breakIdx <= pivotBarIdx) return;

   int searchFrom = MathMax(pivotBarIdx, breakIdx - InpOB_MaxLookback);
   int obIdx = FindOppositeCandle(breakIdx, searchFrom, displacementBullish, open, close);
   if(obIdx < 0)
     {
      Print("SMC_DBG: No opposite candle found (", displacementBullish ? "bull" : "bear", ") break=", breakIdx, " pivot=", pivotBarIdx);
      return;
     }

   OB_Register(obIdx, displacementBullish, internalFlag, time, high, low);
   Print("SMC_DBG: OB registered idx=", obIdx, " dir=", displacementBullish ? "bull" : "bear", " val=", DoubleToString(displacementBullish ? high[obIdx] : low[obIdx], 1));
  }

//+------------------------------------------------------------------+
//| Breaker Block conversion on BOS/MSS confirmation (rules 4,5,9)   |
//|                                                                  |
//| Called from CheckStructureBreaks() on BOS events AND on CBOS/    |
//| MSS confirmation events (the break that confirms the trend       |
//| shift). Scans stored OBs for counter-trend zones that have been  |
//| broken through by a candle CLOSE (Body Close Confirmation rule).  |
//| If broken AND a valid BOS/MSS fires in that direction, converts  |
//| OB → BB.                                                          |
//|                                                                  |
//| BB zone = full candle range (high-low) — entry includes wicks.   |
//| Break confirmation = candle body close only — no wick breaks.    |
//|                                                                  |
//| Requires a confirmed trend AND a BOS/MSS event to activate.      |
//| No BOS/MSS → no Breaker Block.                                    |
//+------------------------------------------------------------------+
void CheckBreakerConversionOnBOS(int i, bool bullishBreak, bool internalFlag,
                                  const double &close[], const double &high[], const double &low[])
  {
   bool confirmed = internalFlag ? internalTrendConfirmed : swingTrendConfirmed;
   int  trendBias = internalFlag ? internalTrendBias : swingTrendBias;
   if(!confirmed) return;

   for(int n = 0; n < g_obCount; n++)
     {
      if(!g_obBoxes[n].active || g_obBoxes[n].isBreaker) continue;
      if(g_obBoxes[n].internal != internalFlag) continue;
      if(i <= g_obBoxes[n].obBarIndex) continue;

      //--- Bearish BB: bearish break in bearish trend, check bullish OBs broken below
      if(trendBias == TREND_BEARISH && !bullishBreak && g_obBoxes[n].isBullish)
        {
         // Scan bars from OB formation to current bar for a BODY CLOSE below OB.bottom
         // (Body Close Confirmation — wick penetration is invalid)
         for(int k = g_obBoxes[n].obBarIndex + 1; k <= i; k++)
           {
            if(close[k] < g_obBoxes[n].bottom)
              {
               g_obBoxes[n].isBreaker = true;
               g_obBoxes[n].isBullish = false;   // convert to bearish BB
               Print("SMC_DBG: Bearish BB created at ", DoubleToString(g_obBoxes[n].bottom, 1), " bar=", k);
               break;
              }
           }
        }

      //--- Bullish BB: bullish break in bullish trend, check bearish OBs broken above
      if(trendBias == TREND_BULLISH && bullishBreak && !g_obBoxes[n].isBullish)
        {
         // Scan bars from OB formation to current bar for a BODY CLOSE above OB.top
         // (Body Close Confirmation — wick penetration is invalid)
         for(int k = g_obBoxes[n].obBarIndex + 1; k <= i; k++)
           {
            if(close[k] > g_obBoxes[n].top)
              {
               g_obBoxes[n].isBreaker = true;
               g_obBoxes[n].isBullish = true;    // convert to bullish BB
               Print("SMC_DBG: Bullish BB created at ", DoubleToString(g_obBoxes[n].top, 1), " bar=", k);
               break;
              }
           }
        }
     }
  }

//--- create/update the chart objects for one zone (rule 8)
//--- Only draws OBs that match the confirmed trend direction.
//--- Counter-trend OBs are hidden until converted to Breaker Blocks.
void OB_Draw(OBBox &b)
  {
   bool   visible;
   color  clr;
   string tag;

   int currentTrend = OB_CurrentTrend();

   if(b.isBreaker)
     {
      // Breaker Blocks are always drawn (they were validated by BOS + trend)
      visible = InpShowBreakerBlocks;
      clr     = b.isBullish ? InpColorBullBB : InpColorBearBB;
      tag     = b.isBullish ? "Bull BB" : "Bear BB";
     }
   else
     {
      // OBs only drawn if they match the confirmed trend
      // If trend is not confirmed (TREND_NONE), no OBs are shown
      if(currentTrend == TREND_NONE)
        {
         OB_DeleteObjects(b);
         return;
        }
      bool matchesTrend = (currentTrend == TREND_BULLISH && b.isBullish) ||
                          (currentTrend == TREND_BEARISH && !b.isBullish);
      if(!matchesTrend)
        {
         // Counter-trend OB: hide until it can become a Breaker Block
         OB_DeleteObjects(b);
         return;
        }
      visible = InpShowOrderBlocks;
      clr     = b.isBullish ? InpColorBullOB : InpColorBearOB;
      tag     = b.isBullish ? "Bull OB" : "Bear OB";
     }

   if(!visible)
     {
      OB_DeleteObjects(b);
      return;
     }

   if(ObjectFind(0, b.boxName) < 0)
      ObjectCreate(0, b.boxName, OBJ_RECTANGLE, 0, b.time1, b.top, b.time2, b.bottom);

   ObjectSetInteger(0, b.boxName, OBJPROP_TIME,  0, b.time1);
   ObjectSetDouble (0, b.boxName, OBJPROP_PRICE, 0, b.top);
   ObjectSetInteger(0, b.boxName, OBJPROP_TIME,  1, b.time2);
   ObjectSetDouble (0, b.boxName, OBJPROP_PRICE, 1, b.bottom);
   ObjectSetInteger(0, b.boxName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, b.boxName, OBJPROP_FILL,  true);
   ObjectSetInteger(0, b.boxName, OBJPROP_BACK,  true);
   ObjectSetInteger(0, b.boxName, OBJPROP_STYLE, b.mitigated ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, b.boxName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, b.boxName, OBJPROP_SELECTABLE, false);

   if(InpOB_ShowLabels)
     {
      double lblPrice = b.isBullish ? b.bottom : b.top;
      if(ObjectFind(0, b.lblName) < 0)
         ObjectCreate(0, b.lblName, OBJ_TEXT, 0, b.time1, lblPrice);
      ObjectSetInteger(0, b.lblName, OBJPROP_TIME,  0, b.time1);
      ObjectSetDouble (0, b.lblName, OBJPROP_PRICE, 0, lblPrice);
      ObjectSetString (0, b.lblName, OBJPROP_TEXT, b.mitigated ? tag + " (mitigated)" : tag);
      ObjectSetInteger(0, b.lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, b.lblName, OBJPROP_FONTSIZE, InpStructureLabelFontSize);
      ObjectSetInteger(0, b.lblName, OBJPROP_ANCHOR, b.isBullish ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, b.lblName, OBJPROP_SELECTABLE, false);
     }
  }

//+------------------------------------------------------------------+
//| Entry point #2 - Zone update + mitigation (rules 6,7,10)         |
//|                                                                  |
//| Runs once per bar over every tracked zone:                       |
//|  1) Active zones are extended to the current bar (rule 6).       |
//|  2) Zones are checked for mitigation - price returning into the  |
//|     zone (rule 7). Mitigated zones stop extending and are frozen |
//|     on the chart as history; they are removed from the active    |
//|     "still tracked" set (rule 10).                                |
//|                                                                  |
//| NOTE: Breaker Block conversion is NOT done here — it happens     |
//| only in CheckBreakerConversionOnBOS(), called on every BOS event |
//| from CheckStructureBreaks(). No BOS → no Breaker Block.          |
//+------------------------------------------------------------------+
void UpdateOrderBlocksAndBreakers(int i, const datetime &time[], const double &open[],
                                   const double &high[], const double &low[], const double &close[])
  {
   for(int n = 0; n < g_obCount; n++)
     {
      if(!g_obBoxes[n].active) continue;

      OBBox b = g_obBoxes[n];
      bool  pastFormation = (i > b.obBarIndex);

      //--- 1) Extend the zone to the right while still active (rule 6) ---
      if(!b.mitigated)
         b.time2 = time[i];

      //--- 2) Mitigation check (rule 7) -----------------------------------
      if(pastFormation && !b.mitigated)
        {
         double touchLow  = InpOB_MitigateByWick ? low[i]  : close[i];
         double touchHigh = InpOB_MitigateByWick ? high[i] : close[i];

         if(b.isBullish && touchLow <= b.top)
            b.mitigated = true;
         else if(!b.isBullish && touchHigh >= b.bottom)
            b.mitigated = true;
        }

      OB_Draw(b);

      if(b.mitigated)
         b.active = false;   // zone stops updating; remains on chart as history

      g_obBoxes[n] = b;
     }
  }

//+------------------------------------------------------------------+
//| Draw or update a structure segment line + midpoint label         |
//+------------------------------------------------------------------+
void DrawStructureLine(string prefix, datetime t1, datetime t2, double price,
                        string tag, color clr, ENUM_LINE_STYLE style,
                        datetime midTime, bool labelAbove, int fontSize)
  {
   string lname = prefix + "_LN_" + IntegerToString((long)t1) + "_" + IntegerToString((long)t2);
   if(ObjectFind(0, lname) < 0)
      ObjectCreate(0, lname, OBJ_TREND, 0, t1, price, t2, price);

   ObjectSetInteger(0, lname, OBJPROP_TIME,  0, t1);
   ObjectSetDouble (0, lname, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, lname, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, lname, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, lname, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, lname, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lname, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lname, OBJPROP_STYLE, style);
   ObjectSetInteger(0, lname, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lname, OBJPROP_BACK, true);
   ObjectSetInteger(0, lname, OBJPROP_SELECTABLE, false);

   string tname = prefix + "_LBL_" + IntegerToString((long)t1) + "_" + IntegerToString((long)t2);
   if(ObjectFind(0, tname) < 0)
      ObjectCreate(0, tname, OBJ_TEXT, 0, midTime, price);

   ObjectSetInteger(0, tname, OBJPROP_TIME,  0, midTime);
   ObjectSetDouble (0, tname, OBJPROP_PRICE, 0, price);
   ObjectSetString (0, tname, OBJPROP_TEXT, tag);
   ObjectSetInteger(0, tname, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, tname, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, tname, OBJPROP_ANCHOR, labelAbove ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, tname, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Update just the label text and color of an existing structure    |
//+------------------------------------------------------------------+
void UpdateStructureLabel(datetime t1, datetime t2, string prefix,
                           string newTag, color newClr)
  {
   string tname = prefix + "_LBL_" + IntegerToString((long)t1) + "_" + IntegerToString((long)t2);
   if(ObjectFind(0, tname) >= 0)
     {
      ObjectSetString (0, tname, OBJPROP_TEXT, newTag);
      ObjectSetInteger(0, tname, OBJPROP_COLOR, newClr);
     }
   string lname = prefix + "_LN_" + IntegerToString((long)t1) + "_" + IntegerToString((long)t2);
   if(ObjectFind(0, lname) >= 0)
      ObjectSetInteger(0, lname, OBJPROP_COLOR, newClr);
  }

//+------------------------------------------------------------------+
//| Draw swing point label (HH/HL/LH/LL)                            |
//+------------------------------------------------------------------+
void DrawSwingPointLabel(string prefix, datetime t, double price, string tag,
                          color clr, bool above, int fontSize)
  {
   string name = prefix + "_PT_" + IntegerToString((long)t) + "_" + tag;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME,  0, t);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString (0, name, OBJPROP_TEXT, tag);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Draw / update post-CBOS IDM horizontal level                     |
//| Extends right from startTime, updated each bar until broken      |
//+------------------------------------------------------------------+
void DrawIDMLevel(IDMLevel &lvl, datetime currentTime)
  {
   if(!lvl.active) return;

   // Update the horizontal line end to current bar
   if(ObjectFind(0, lvl.lineName) < 0)
      ObjectCreate(0, lvl.lineName, OBJ_TREND, 0, lvl.startTime, lvl.price, currentTime, lvl.price);

   ObjectSetInteger(0, lvl.lineName, OBJPROP_TIME,  0, lvl.startTime);
   ObjectSetDouble (0, lvl.lineName, OBJPROP_PRICE, 0, lvl.price);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_TIME,  1, currentTime);
   ObjectSetDouble (0, lvl.lineName, OBJPROP_PRICE, 1, lvl.price);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_COLOR, InpColorIDMLevel);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lvl.lineName, OBJPROP_SELECTABLE, false);

   // Label at right edge
   if(ObjectFind(0, lvl.lblName) < 0)
      ObjectCreate(0, lvl.lblName, OBJ_TEXT, 0, currentTime, lvl.price);
   ObjectSetInteger(0, lvl.lblName, OBJPROP_TIME,  0, currentTime);
   ObjectSetDouble (0, lvl.lblName, OBJPROP_PRICE, 0, lvl.price);
   ObjectSetString (0, lvl.lblName, OBJPROP_TEXT, "IDM");
   ObjectSetInteger(0, lvl.lblName, OBJPROP_COLOR, InpColorIDMLevel);
   ObjectSetInteger(0, lvl.lblName, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, lvl.lblName, OBJPROP_ANCHOR, lvl.isBullish ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, lvl.lblName, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Mark IDM level as Trap (update label/color)                      |
//+------------------------------------------------------------------+
void MarkIDMLevelAsTrap(IDMLevel &lvl)
  {
   if(ObjectFind(0, lvl.lblName) >= 0)
     {
      ObjectSetString (0, lvl.lblName, OBJPROP_TEXT, "Trap");
      ObjectSetInteger(0, lvl.lblName, OBJPROP_COLOR, InpColorTrap);
     }
   if(ObjectFind(0, lvl.lineName) >= 0)
      ObjectSetInteger(0, lvl.lineName, OBJPROP_COLOR, InpColorTrap);
  }

//+------------------------------------------------------------------+
//| Strong / Weak trailing lines                                     |
//+------------------------------------------------------------------+
void UpdateTrailingLines(datetime currentTime)
  {
   string topLine = "SMC_TRAIL_TOP_LN";
   string topLbl  = "SMC_TRAIL_TOP_LBL";
   string botLine = "SMC_TRAIL_BOT_LN";
   string botLbl  = "SMC_TRAIL_BOT_LBL";

   if(ObjectFind(0, topLine) < 0)
      ObjectCreate(0, topLine, OBJ_TREND, 0, trailing.lastTopTime, trailing.top, currentTime, trailing.top);
   ObjectSetInteger(0, topLine, OBJPROP_TIME,  0, trailing.lastTopTime);
   ObjectSetDouble (0, topLine, OBJPROP_PRICE, 0, trailing.top);
   ObjectSetInteger(0, topLine, OBJPROP_TIME,  1, currentTime);
   ObjectSetDouble (0, topLine, OBJPROP_PRICE, 1, trailing.top);
   ObjectSetInteger(0, topLine, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, topLine, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, topLine, OBJPROP_COLOR, InpColorBearBOS);
   ObjectSetInteger(0, topLine, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, topLine, OBJPROP_SELECTABLE, false);

   if(ObjectFind(0, topLbl) < 0)
      ObjectCreate(0, topLbl, OBJ_TEXT, 0, currentTime, trailing.top);
   ObjectSetInteger(0, topLbl, OBJPROP_TIME,  0, currentTime);
   ObjectSetDouble (0, topLbl, OBJPROP_PRICE, 0, trailing.top);
   ObjectSetString (0, topLbl, OBJPROP_TEXT, swingTrendBias==TREND_BEARISH ? "Strong High" : "Weak High");
   ObjectSetInteger(0, topLbl, OBJPROP_COLOR, InpColorBearBOS);
   ObjectSetInteger(0, topLbl, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, topLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, topLbl, OBJPROP_SELECTABLE, false);

   if(ObjectFind(0, botLine) < 0)
      ObjectCreate(0, botLine, OBJ_TREND, 0, trailing.lastBottomTime, trailing.bottom, currentTime, trailing.bottom);
   ObjectSetInteger(0, botLine, OBJPROP_TIME,  0, trailing.lastBottomTime);
   ObjectSetDouble (0, botLine, OBJPROP_PRICE, 0, trailing.bottom);
   ObjectSetInteger(0, botLine, OBJPROP_TIME,  1, currentTime);
   ObjectSetDouble (0, botLine, OBJPROP_PRICE, 1, trailing.bottom);
   ObjectSetInteger(0, botLine, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, botLine, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, botLine, OBJPROP_COLOR, InpColorBOS);
   ObjectSetInteger(0, botLine, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, botLine, OBJPROP_SELECTABLE, false);

   if(ObjectFind(0, botLbl) < 0)
      ObjectCreate(0, botLbl, OBJ_TEXT, 0, currentTime, trailing.bottom);
   ObjectSetInteger(0, botLbl, OBJPROP_TIME,  0, currentTime);
   ObjectSetDouble (0, botLbl, OBJPROP_PRICE, 0, trailing.bottom);
   ObjectSetString (0, botLbl, OBJPROP_TEXT, swingTrendBias==TREND_BULLISH ? "Strong Low" : "Weak Low");
   ObjectSetInteger(0, botLbl, OBJPROP_COLOR, InpColorBOS);
   ObjectSetInteger(0, botLbl, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, botLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, botLbl, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Premium / Discount Array Module                                   |
//|                                                                  |
//| Standalone module — does not touch any existing structure logic. |
//| Uses the trailing extremes (Strong/Weak HL) and swing trend bias |
//| to calculate PD array levels for trade entry signals.            |
//|                                                                  |
//| BULLISH TREND:                                                   |
//|   StrongLow = trailing.bottom, WeakHigh = trailing.top           |
//|   Range = WeakHigh - StrongLow                                   |
//|   DiscountLevel = StrongLow + Range * InpPDRetracement            |
//|   0.0 at WeakHigh, 1.0 at StrongLow                              |
//|   BUY when price <= DiscountLevel                                 |
//|                                                                  |
//| BEARISH TREND:                                                   |
//|   StrongHigh = trailing.top, WeakLow = trailing.bottom            |
//|   Range = StrongHigh - WeakLow                                    |
//|   PremiumLevel = WeakLow + Range * InpPDRetracement               |
//|   0.0 at WeakLow, 1.0 at StrongHigh                               |
//|   SELL when price >= PremiumLevel                                 |
//+------------------------------------------------------------------+
void UpdatePDArray(datetime currentTime, double currentClose)
  {
   if(!InpShowPDArray || !trailing.valid) return;

   double level0, level1, levelRetrace;

   // --- BULLISH TREND ---
   if(swingTrendBias == TREND_BULLISH)
     {
      double strongLow  = trailing.bottom;
      double weakHigh   = trailing.top;
      double range      = weakHigh - strongLow;
      if(range <= 0) return;

      level0       = weakHigh;                         // 0.0
      level1       = strongLow;                        // 1.0
      levelRetrace = strongLow + range * InpPDRetracement; // 0.60

      // Draw 0.0 line at WeakHigh
      string n0 = "SMC_PD_00_LN";
      if(ObjectFind(0, n0) < 0)
         ObjectCreate(0, n0, OBJ_TREND, 0, trailing.lastTopTime, level0, currentTime, level0);
      ObjectSetInteger(0, n0, OBJPROP_TIME,  0, trailing.lastTopTime);
      ObjectSetDouble (0, n0, OBJPROP_PRICE, 0, level0);
      ObjectSetInteger(0, n0, OBJPROP_TIME,  1, currentTime);
      ObjectSetDouble (0, n0, OBJPROP_PRICE, 1, level0);
      ObjectSetInteger(0, n0, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, n0, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, n0, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n0, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, n0, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n0, OBJPROP_SELECTABLE, false);
      string l0 = "SMC_PD_00_LBL";
      if(ObjectFind(0, l0) < 0)
         ObjectCreate(0, l0, OBJ_TEXT, 0, currentTime, level0);
      ObjectSetInteger(0, l0, OBJPROP_TIME,  0, currentTime);
      ObjectSetDouble (0, l0, OBJPROP_PRICE, 0, level0);
      ObjectSetString (0, l0, OBJPROP_TEXT, "0.0 (Weak High)");
      ObjectSetInteger(0, l0, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, l0, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, l0, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, l0, OBJPROP_SELECTABLE, false);

      // Draw 1.0 line at StrongLow
      string n1 = "SMC_PD_10_LN";
      if(ObjectFind(0, n1) < 0)
         ObjectCreate(0, n1, OBJ_TREND, 0, trailing.lastBottomTime, level1, currentTime, level1);
      ObjectSetInteger(0, n1, OBJPROP_TIME,  0, trailing.lastBottomTime);
      ObjectSetDouble (0, n1, OBJPROP_PRICE, 0, level1);
      ObjectSetInteger(0, n1, OBJPROP_TIME,  1, currentTime);
      ObjectSetDouble (0, n1, OBJPROP_PRICE, 1, level1);
      ObjectSetInteger(0, n1, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, n1, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, n1, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n1, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, n1, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n1, OBJPROP_SELECTABLE, false);
      string l1 = "SMC_PD_10_LBL";
      if(ObjectFind(0, l1) < 0)
         ObjectCreate(0, l1, OBJ_TEXT, 0, currentTime, level1);
      ObjectSetInteger(0, l1, OBJPROP_TIME,  0, currentTime);
      ObjectSetDouble (0, l1, OBJPROP_PRICE, 0, level1);
      ObjectSetString (0, l1, OBJPROP_TEXT, "1.0 (Strong Low)");
      ObjectSetInteger(0, l1, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, l1, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, l1, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, l1, OBJPROP_SELECTABLE, false);

      // Draw retracement level (0.60)
      string nr = "SMC_PD_RT_LN";
      if(ObjectFind(0, nr) < 0)
         ObjectCreate(0, nr, OBJ_TREND, 0, trailing.lastBottomTime, levelRetrace, currentTime, levelRetrace);
      ObjectSetInteger(0, nr, OBJPROP_TIME,  0, trailing.lastBottomTime);
      ObjectSetDouble (0, nr, OBJPROP_PRICE, 0, levelRetrace);
      ObjectSetInteger(0, nr, OBJPROP_TIME,  1, currentTime);
      ObjectSetDouble (0, nr, OBJPROP_PRICE, 1, levelRetrace);
      ObjectSetInteger(0, nr, OBJPROP_COLOR, InpColorDiscount);
      ObjectSetInteger(0, nr, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nr, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nr, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, nr, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nr, OBJPROP_SELECTABLE, false);
      string lr = "SMC_PD_RT_LBL";
      if(ObjectFind(0, lr) < 0)
         ObjectCreate(0, lr, OBJ_TEXT, 0, currentTime, levelRetrace);
      ObjectSetInteger(0, lr, OBJPROP_TIME,  0, currentTime);
      ObjectSetDouble (0, lr, OBJPROP_PRICE, 0, levelRetrace);
      string rtLabel;
      StringConcatenate(rtLabel, DoubleToString(InpPDRetracement * 100, 0), "% Discount");
      ObjectSetString (0, lr, OBJPROP_TEXT, rtLabel);
      ObjectSetInteger(0, lr, OBJPROP_COLOR, InpColorDiscount);
      ObjectSetInteger(0, lr, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, lr, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, lr, OBJPROP_SELECTABLE, false);

      // Monitor: BUY signal when price reaches discount zone
      if(currentClose <= levelRetrace)
        {
         double sl = level1 - InpSLBufferPoints * Point();
         string sig = "SMC_PD_BUY_SIG";
         if(ObjectFind(0, sig) < 0)
            ObjectCreate(0, sig, OBJ_ARROW_BUY, 0, currentTime, currentClose);
         ObjectSetInteger(0, sig, OBJPROP_TIME,  0, currentTime);
         ObjectSetDouble (0, sig, OBJPROP_PRICE, 0, currentClose);
         ObjectSetInteger(0, sig, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, sig, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, sig, OBJPROP_SELECTABLE, false);
        }
     }

   // --- BEARISH TREND ---
   if(swingTrendBias == TREND_BEARISH)
     {
      double strongHigh = trailing.top;
      double weakLow    = trailing.bottom;
      double range      = strongHigh - weakLow;
      if(range <= 0) return;

      level0       = weakLow;                          // 0.0
      level1       = strongHigh;                       // 1.0
      levelRetrace = weakLow + range * InpPDRetracement; // 0.60

      // Draw 0.0 line at WeakLow
      string n0 = "SMC_PD_00_LN";
      if(ObjectFind(0, n0) < 0)
         ObjectCreate(0, n0, OBJ_TREND, 0, trailing.lastBottomTime, level0, currentTime, level0);
      ObjectSetInteger(0, n0, OBJPROP_TIME,  0, trailing.lastBottomTime);
      ObjectSetDouble (0, n0, OBJPROP_PRICE, 0, level0);
      ObjectSetInteger(0, n0, OBJPROP_TIME,  1, currentTime);
      ObjectSetDouble (0, n0, OBJPROP_PRICE, 1, level0);
      ObjectSetInteger(0, n0, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, n0, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, n0, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n0, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, n0, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n0, OBJPROP_SELECTABLE, false);
      string l0 = "SMC_PD_00_LBL";
      if(ObjectFind(0, l0) < 0)
         ObjectCreate(0, l0, OBJ_TEXT, 0, currentTime, level0);
      ObjectSetInteger(0, l0, OBJPROP_TIME,  0, currentTime);
      ObjectSetDouble (0, l0, OBJPROP_PRICE, 0, level0);
      ObjectSetString (0, l0, OBJPROP_TEXT, "0.0 (Weak Low)");
      ObjectSetInteger(0, l0, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, l0, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, l0, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, l0, OBJPROP_SELECTABLE, false);

      // Draw 1.0 line at StrongHigh
      string n1 = "SMC_PD_10_LN";
      if(ObjectFind(0, n1) < 0)
         ObjectCreate(0, n1, OBJ_TREND, 0, trailing.lastTopTime, level1, currentTime, level1);
      ObjectSetInteger(0, n1, OBJPROP_TIME,  0, trailing.lastTopTime);
      ObjectSetDouble (0, n1, OBJPROP_PRICE, 0, level1);
      ObjectSetInteger(0, n1, OBJPROP_TIME,  1, currentTime);
      ObjectSetDouble (0, n1, OBJPROP_PRICE, 1, level1);
      ObjectSetInteger(0, n1, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, n1, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, n1, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n1, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, n1, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n1, OBJPROP_SELECTABLE, false);
      string l1 = "SMC_PD_10_LBL";
      if(ObjectFind(0, l1) < 0)
         ObjectCreate(0, l1, OBJ_TEXT, 0, currentTime, level1);
      ObjectSetInteger(0, l1, OBJPROP_TIME,  0, currentTime);
      ObjectSetDouble (0, l1, OBJPROP_PRICE, 0, level1);
      ObjectSetString (0, l1, OBJPROP_TEXT, "1.0 (Strong High)");
      ObjectSetInteger(0, l1, OBJPROP_COLOR, InpColorPDLine);
      ObjectSetInteger(0, l1, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, l1, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, l1, OBJPROP_SELECTABLE, false);

      // Draw retracement level (0.60)
      string nr = "SMC_PD_RT_LN";
      if(ObjectFind(0, nr) < 0)
         ObjectCreate(0, nr, OBJ_TREND, 0, trailing.lastBottomTime, levelRetrace, currentTime, levelRetrace);
      ObjectSetInteger(0, nr, OBJPROP_TIME,  0, trailing.lastBottomTime);
      ObjectSetDouble (0, nr, OBJPROP_PRICE, 0, levelRetrace);
      ObjectSetInteger(0, nr, OBJPROP_TIME,  1, currentTime);
      ObjectSetDouble (0, nr, OBJPROP_PRICE, 1, levelRetrace);
      ObjectSetInteger(0, nr, OBJPROP_COLOR, InpColorPremium);
      ObjectSetInteger(0, nr, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nr, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nr, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, nr, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nr, OBJPROP_SELECTABLE, false);
      string lr = "SMC_PD_RT_LBL";
      if(ObjectFind(0, lr) < 0)
         ObjectCreate(0, lr, OBJ_TEXT, 0, currentTime, levelRetrace);
      ObjectSetInteger(0, lr, OBJPROP_TIME,  0, currentTime);
      ObjectSetDouble (0, lr, OBJPROP_PRICE, 0, levelRetrace);
      string rtLabel;
      StringConcatenate(rtLabel, DoubleToString(InpPDRetracement * 100, 0), "% Premium");
      ObjectSetString (0, lr, OBJPROP_TEXT, rtLabel);
      ObjectSetInteger(0, lr, OBJPROP_COLOR, InpColorPremium);
      ObjectSetInteger(0, lr, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, lr, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lr, OBJPROP_SELECTABLE, false);

      // Monitor: SELL signal when price reaches premium zone
      if(currentClose >= levelRetrace)
        {
         double sl = level1 + InpSLBufferPoints * Point();
         string sig = "SMC_PD_SELL_SIG";
         if(ObjectFind(0, sig) < 0)
            ObjectCreate(0, sig, OBJ_ARROW_SELL, 0, currentTime, currentClose);
         ObjectSetInteger(0, sig, OBJPROP_TIME,  0, currentTime);
         ObjectSetDouble (0, sig, OBJPROP_PRICE, 0, currentClose);
         ObjectSetInteger(0, sig, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, sig, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, sig, OBJPROP_SELECTABLE, false);
        }
     }
  }

//+------------------------------------------------------------------+
//| Pivot detection                                                  |
//+------------------------------------------------------------------+
void ProcessPivots(int i, int length, const datetime &time[],
                    const double &high[], const double &low[], bool internal)
  {
   if(i < length) return;

   double hh = Highest(high, i-length+1, i);
   double ll = Lowest (low,  i-length+1, i);

   bool newLegHigh = high[i-length] > hh;
   bool newLegLow  = low[i-length]  < ll;

   int prevLeg = internal ? internalLeg : swingLeg;
   int newLeg  = prevLeg;
   if(newLegHigh)      newLeg = LEG_BEARISH;
   else if(newLegLow)  newLeg = LEG_BULLISH;

   bool pivotLowConfirmed  = (prevLeg != -1) && (newLeg != prevLeg) && (newLeg == LEG_BULLISH);
   bool pivotHighConfirmed = (prevLeg != -1) && (newLeg != prevLeg) && (newLeg == LEG_BEARISH);

   if(internal) internalLeg = newLeg; else swingLeg = newLeg;

   int pivBarIdx = i - length;

   if(pivotLowConfirmed)
     {
      PivotPoint p = internal ? internalLow : swingLow;
      p.lastPrice = p.valid ? p.price : low[pivBarIdx];
      p.price     = low[pivBarIdx];
      p.time      = time[pivBarIdx];
      p.barIndex  = pivBarIdx;
      p.crossed   = false;
      p.valid     = true;
      if(internal) internalLow = p; else swingLow = p;

      if(!internal)
        {
         trailing.bottom         = p.price;
         trailing.lastBottomTime = p.time;
         trailing.valid          = true;
         if(InpShowSwingLabels)
            DrawSwingPointLabel("SMC_SWING", p.time, p.price,
                                 (p.price < p.lastPrice) ? "LL" : "HL",
                                 InpColorBOS, true, InpSwingPointFontSize);
        }
     }

   if(pivotHighConfirmed)
     {
      PivotPoint p = internal ? internalHigh : swingHigh;
      p.lastPrice = p.valid ? p.price : high[pivBarIdx];
      p.price     = high[pivBarIdx];
      p.time      = time[pivBarIdx];
      p.barIndex  = pivBarIdx;
      p.crossed   = false;
      p.valid     = true;
      if(internal) internalHigh = p; else swingHigh = p;

      if(!internal)
        {
         trailing.top         = p.price;
         trailing.lastTopTime = p.time;
         trailing.valid       = true;
         if(InpShowSwingLabels)
            DrawSwingPointLabel("SMC_SWING", p.time, p.price,
                                 (p.price > p.lastPrice) ? "HH" : "LH",
                                 InpColorBearBOS, false, InpSwingPointFontSize);
        }
     }
  }

//+------------------------------------------------------------------+
//| Place a post-CBOS IDM level                                      |
//| For bullish CBOS: find lowest low between pivotBarIndex and      |
//|   breakBarIndex (the CBOS bar)                                   |
//| For bearish CBOS: find highest high in that same range           |
//+------------------------------------------------------------------+
void PlacePostCBOSIDMLevel(IDMLevel &lvl, bool isBullish,
                            int pivotBarIndex, int breakBarIndex,
                            const double &high[], const double &low[],
                            const datetime &time[], bool internal)
  {
   int fromBar = MathMin(pivotBarIndex, breakBarIndex);
   int toBar   = MathMax(pivotBarIndex, breakBarIndex);

   double idmPrice;
   if(isBullish)
      idmPrice = Lowest(low, fromBar, toBar);
   else
      idmPrice = Highest(high, fromBar, toBar);

   string pfx = internal ? "SMC_INT_IDMLVL" : "SMC_SWING_IDMLVL";
   string uid  = IntegerToString((long)time[breakBarIndex]);

   lvl.active     = true;
   lvl.isBullish  = isBullish;
   lvl.price      = idmPrice;
   lvl.startTime  = time[breakBarIndex];
   lvl.broken     = false;
   lvl.lineName   = pfx + "_LN_" + uid;
   lvl.lblName    = pfx + "_LBL_" + uid;
  }

//+------------------------------------------------------------------+
//| Check if post-CBOS IDM level has been broken, and handle it     |
//+------------------------------------------------------------------+
void CheckIDMLevel(IDMLevel &lvl, int i, const double &close[], const datetime &time[],
                    int &seqState, PendingIDM &pending, bool internal,
                    const double &high[], const double &low[])
  {
   if(!lvl.active || lvl.broken) return;

   bool broken = false;
   if(lvl.isBullish && close[i] < lvl.price)  broken = true;  // bearish close through bull IDM level
   if(!lvl.isBullish && close[i] > lvl.price) broken = true;  // bullish close through bear IDM level

   if(broken)
     {
      lvl.broken = true;
      MarkIDMLevelAsTrap(lvl);
      lvl.active = false;
      // After trap, next BOS in the IDM-break direction will be labeled TBOS
      // Signal this by setting pending state so next BOS becomes TBOS
      // We use a special IDM state to note TBOS is expected
      // For simplicity, set seqState so the BOS engine picks it up:
      // We mark: seqState = special "awaiting TBOS" using SEQ_IDM_BULL/BEAR
      // (direction of the break = direction of the trap break)
      if(lvl.isBullish)
         seqState = SEQ_IDM_BEAR;   // IDM level was bullish, it got broken bearishly => next bear BOS = TBOS
      else
         seqState = SEQ_IDM_BULL;   // IDM level was bearish, it got broken bullishly => next bull BOS = TBOS

      // Mark pending as a "from-IDM-level" trap (no visible IDM segment needed)
      pending.active        = true;
      pending.isBullish     = !lvl.isBullish;  // the break direction
      pending.price         = lvl.price;
      pending.time          = time[i];
      pending.barIndex      = i;
      pending.pivotPrice    = lvl.price;
      pending.pivotTime     = lvl.startTime;
      pending.pivotBarIndex = i;
      pending.objPrefix     = "";   // no IDM segment was drawn for this (it was the level label)
     }
  }

//+------------------------------------------------------------------+
//| Main structure break + sequence logic                            |
//|                                                                  |
//| State machine per timeframe (swing / internal):                  |
//|   trendBias = TREND_NONE  : no bias yet, first breaks are BOS   |
//|   seqState  = SEQ_NONE    : no pending IDM                      |
//|                                                                  |
//| On every break:                                                  |
//|   SEQ_NONE + same/no bias      -> BOS  (bias set/confirmed)     |
//|   SEQ_NONE + opposite bias     -> IDM  (seqState -> IDM_BULL/   |
//|                                          IDM_BEAR)               |
//|   SEQ_IDM_BULL + bull break    -> IDM->CHoCH/MSS + CBOS + level |
//|   SEQ_IDM_BULL + bear break    -> IDM->Trap + TBOS  (restart)   |
//|   SEQ_IDM_BEAR + bear break    -> IDM->CHoCH/MSS + CBOS + level |
//|   SEQ_IDM_BEAR + bull break    -> IDM->Trap + TBOS  (restart)   |
//+------------------------------------------------------------------+
void CheckStructureBreaks(int i, const datetime &time[], const double &open[], const double &close[],
                           const double &high[], const double &low[], bool internal)
  {
   PivotPoint pHigh  = internal ? internalHigh : swingHigh;
   PivotPoint pLow   = internal ? internalLow  : swingLow;
   int trendBias     = internal ? internalTrendBias : swingTrendBias;
   int seqState      = internal ? intSeqState : swingSeqState;
   PendingIDM pending = internal ? intPendingIDM : swingPendingIDM;

   bool   showThis = internal ? InpShowInternalStructure : InpShowSwingStructure;
   ENUM_LINE_STYLE lstyle = internal ? STYLE_DASH : STYLE_SOLID;
   int    fontSize = InpStructureLabelFontSize;
   string prefix   = internal ? "SMC_INT" : "SMC_SWING";

   // Deduplicate: skip internal break if it's at the exact same level as the swing break
   bool extraBull = true, extraBear = true;
   if(internal)
     {
      extraBull = (!swingHigh.valid) || (pHigh.price != swingHigh.price);
      extraBear = (!swingLow.valid)  || (pLow.price  != swingLow.price);
     }

   //------------------------------------------------------------------
   // Helper lambda-style inline: emit IDM label and set pending state
   //------------------------------------------------------------------
   // (done inline below for each direction)

   //------------------------------------------------------------------
   // BULLISH BREAK: close crosses above pivot high
   //------------------------------------------------------------------
   if(pHigh.valid && !pHigh.crossed && close[i] > pHigh.price && extraBull)
     {
      pHigh.crossed = true;
      if(internal) internalHigh = pHigh; else swingHigh = pHigh;

      int midIdx = (pHigh.barIndex + i) / 2;

      if(seqState == SEQ_NONE)
        {
         if(trendBias == TREND_NONE || trendBias == TREND_BULLISH)
           {
            //--- BOS: in-trend or first-ever break upward
            if(showThis)
               DrawStructureLine(prefix, pHigh.time, time[i], pHigh.price, "BOS",
                                  InpColorBOS, lstyle, time[midIdx], false, fontSize);
            if(internal) BufIntBullBOS[i]   = pHigh.price;
            else         BufSwingBullBOS[i] = pHigh.price;
            // Set/confirm bullish bias
            if(internal) internalTrendBias = TREND_BULLISH;
            else         swingTrendBias    = TREND_BULLISH;
            // OB/BB module: bullish displacement -> last bearish candle = OB (rules 2,3)
            DetectOrderBlockOnBreak(i, pHigh.barIndex, true, internal, time, open, high, low, close);
            // Check for Breaker Block conversion on this BOS (rules 4,5,9)
            CheckBreakerConversionOnBOS(i, true, internal, close, high, low);
           }
         else // trendBias == TREND_BEARISH  -> opposite direction
           {
            //--- IDM: against current bearish bias
            if(showThis)
               DrawStructureLine(prefix, pHigh.time, time[i], pHigh.price, "IDM",
                                  InpColorIDM, lstyle, time[midIdx], false, fontSize);
            pending.active        = true;
            pending.isBullish     = true;
            pending.price         = pHigh.price;
            pending.time          = time[i];
            pending.barIndex      = i;
            pending.pivotPrice    = pHigh.price;
            pending.pivotTime     = pHigh.time;
            pending.pivotBarIndex = pHigh.barIndex;
            pending.objPrefix     = prefix;
            seqState = SEQ_IDM_BULL;
           }
        }
      else if(seqState == SEQ_IDM_BULL)
        {
         //--- Same direction as pending IDM -> confirm: IDM->CHoCH/MSS, this break->CBOS
         string chochTag = internal ? "MSS" : "CHoCH";
         if(showThis && pending.objPrefix != "")
            UpdateStructureLabel(pending.pivotTime, pending.time, pending.objPrefix,
                                  chochTag, InpColorCHoCH);
         if(showThis)
            DrawStructureLine(prefix, pHigh.time, time[i], pHigh.price, "CBOS",
                               InpColorCBOS, lstyle, time[midIdx], false, fontSize);
         if(internal) { BufIntBullCHoCH[i]   = pHigh.price; BufIntBullBOS[i]   = pHigh.price; }
         else         { BufSwingBullCHoCH[i] = pHigh.price; BufSwingBullBOS[i] = pHigh.price; }
         // Flip bias to bullish
         if(internal) internalTrendBias = TREND_BULLISH;
         else         swingTrendBias    = TREND_BULLISH;
         // Trend confirmed: bullish BOS followed by bullish MSS (rules 4,5)
         if(internal) internalTrendConfirmed = true;
         else         swingTrendConfirmed    = true;
         // Place post-CBOS IDM level (lowest low between pivot and break bar)
         IDMLevel newLvl;
         PlacePostCBOSIDMLevel(newLvl, true, pHigh.barIndex, i, high, low, time, internal);
         if(internal) intIDMLevel = newLvl; else swingIDMLevel = newLvl;
         // OB/BB module: bullish MSS -> last bearish candle before the
         // displacement that produced it = OB (rules 2,3)
         DetectOrderBlockOnBreak(i, pHigh.barIndex, true, internal, time, open, high, low, close);
         // Check for Breaker Block conversion on this MSS/CBOS
         CheckBreakerConversionOnBOS(i, true, internal, close, high, low);
         // Reset sequence
         seqState       = SEQ_NONE;
         pending.active = false;
        }
      else if(seqState == SEQ_IDM_BEAR)
        {
         //--- Opposite of pending bearish IDM -> IDM->Trap, this break->TBOS, restart
         if(showThis && pending.objPrefix != "")
            UpdateStructureLabel(pending.pivotTime, pending.time, pending.objPrefix,
                                  "Trap", InpColorTrap);
         if(showThis)
            DrawStructureLine(prefix, pHigh.time, time[i], pHigh.price, "TBOS",
                               InpColorTBOS, lstyle, time[midIdx], false, fontSize);
         if(internal) BufIntBullBOS[i]   = pHigh.price;
         else         BufSwingBullBOS[i] = pHigh.price;
         // Bias stays bearish (original direction confirmed by trap resolution)
         // Restart: next opposite break will be fresh IDM
         seqState       = SEQ_NONE;
         pending.active = false;
        }

      // Write back local copies to globals
      if(internal) { intSeqState = seqState; intPendingIDM = pending; }
      else         { swingSeqState = seqState; swingPendingIDM = pending; }
     }

   // Re-read state in case bullish break already updated it
   seqState  = internal ? intSeqState  : swingSeqState;
   pending   = internal ? intPendingIDM : swingPendingIDM;
   trendBias = internal ? internalTrendBias : swingTrendBias;

   //------------------------------------------------------------------
   // BEARISH BREAK: close crosses below pivot low
   //------------------------------------------------------------------
   if(pLow.valid && !pLow.crossed && close[i] < pLow.price && extraBear)
     {
      pLow.crossed = true;
      if(internal) internalLow = pLow; else swingLow = pLow;

      int midIdx = (pLow.barIndex + i) / 2;

      if(seqState == SEQ_NONE)
        {
         if(trendBias == TREND_NONE || trendBias == TREND_BEARISH)
           {
            //--- BOS: in-trend or first-ever break downward
            if(showThis)
               DrawStructureLine(prefix, pLow.time, time[i], pLow.price, "BOS",
                                  InpColorBearBOS, lstyle, time[midIdx], true, fontSize);
            if(internal) BufIntBearBOS[i]   = pLow.price;
            else         BufSwingBearBOS[i] = pLow.price;
            // Set/confirm bearish bias
            if(internal) internalTrendBias = TREND_BEARISH;
            else         swingTrendBias    = TREND_BEARISH;
            // OB/BB module: bearish displacement -> last bullish candle = OB (rules 2,3)
            DetectOrderBlockOnBreak(i, pLow.barIndex, false, internal, time, open, high, low, close);
            // Check for Breaker Block conversion on this BOS (rules 4,5,9)
            CheckBreakerConversionOnBOS(i, false, internal, close, high, low);
           }
         else // trendBias == TREND_BULLISH  -> opposite direction
           {
            //--- IDM: against current bullish bias
            if(showThis)
               DrawStructureLine(prefix, pLow.time, time[i], pLow.price, "IDM",
                                  InpColorIDM, lstyle, time[midIdx], true, fontSize);
            pending.active        = true;
            pending.isBullish     = false;
            pending.price         = pLow.price;
            pending.time          = time[i];
            pending.barIndex      = i;
            pending.pivotPrice    = pLow.price;
            pending.pivotTime     = pLow.time;
            pending.pivotBarIndex = pLow.barIndex;
            pending.objPrefix     = prefix;
            seqState = SEQ_IDM_BEAR;
           }
        }
      else if(seqState == SEQ_IDM_BEAR)
        {
         //--- Same direction as pending bearish IDM -> confirm: IDM->CHoCH/MSS, this->CBOS
         string chochTag = internal ? "MSS" : "CHoCH";
         if(showThis && pending.objPrefix != "")
            UpdateStructureLabel(pending.pivotTime, pending.time, pending.objPrefix,
                                  chochTag, InpColorCHoCH);
         if(showThis)
            DrawStructureLine(prefix, pLow.time, time[i], pLow.price, "CBOS",
                               InpColorCBOS, lstyle, time[midIdx], true, fontSize);
         if(internal) { BufIntBearCHoCH[i]   = pLow.price; BufIntBearBOS[i]   = pLow.price; }
         else         { BufSwingBearCHoCH[i] = pLow.price; BufSwingBearBOS[i] = pLow.price; }
         // Flip bias to bearish
         if(internal) internalTrendBias = TREND_BEARISH;
         else         swingTrendBias    = TREND_BEARISH;
         // Trend confirmed: bearish BOS followed by bearish MSS (rules 4,5)
         if(internal) internalTrendConfirmed = true;
         else         swingTrendConfirmed    = true;
         // Place post-CBOS IDM level (highest high between pivot and break bar)
         IDMLevel newLvl;
         PlacePostCBOSIDMLevel(newLvl, false, pLow.barIndex, i, high, low, time, internal);
         if(internal) intIDMLevel = newLvl; else swingIDMLevel = newLvl;
         // OB/BB module: bearish MSS -> last bullish candle before the
         // displacement that produced it = OB (rules 2,3)
         DetectOrderBlockOnBreak(i, pLow.barIndex, false, internal, time, open, high, low, close);
         // Check for Breaker Block conversion on this MSS/CBOS
         CheckBreakerConversionOnBOS(i, false, internal, close, high, low);
         // Reset sequence
         seqState       = SEQ_NONE;
         pending.active = false;
        }
      else if(seqState == SEQ_IDM_BULL)
        {
         //--- Opposite of pending bullish IDM -> IDM->Trap, this->TBOS, restart
         if(showThis && pending.objPrefix != "")
            UpdateStructureLabel(pending.pivotTime, pending.time, pending.objPrefix,
                                  "Trap", InpColorTrap);
         if(showThis)
            DrawStructureLine(prefix, pLow.time, time[i], pLow.price, "TBOS",
                               InpColorTBOS, lstyle, time[midIdx], true, fontSize);
         if(internal) BufIntBearBOS[i]   = pLow.price;
         else         BufSwingBearBOS[i] = pLow.price;
         // Bias stays bullish (original direction confirmed by trap resolution)
         seqState       = SEQ_NONE;
         pending.active = false;
        }

      // Write back local copies to globals
      if(internal) { intSeqState = seqState; intPendingIDM = pending; }
      else         { swingSeqState = seqState; swingPendingIDM = pending; }
     }
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int maxLen = MathMax(InpSwingLength, InpInternalLength);
   if(rates_total < maxLen + 2) return(0);

   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   int start;
   if(prev_calculated == 0)
     {
      swingHigh.valid = false;  swingLow.valid = false;
      internalHigh.valid = false; internalLow.valid = false;
      swingLeg = -1; internalLeg = -1;
      swingTrendBias = TREND_NONE; internalTrendBias = TREND_NONE;
      swingTrendConfirmed = false; internalTrendConfirmed = false;
      trailing.valid = false;

      swingSeqState = SEQ_NONE; intSeqState = SEQ_NONE;
      swingPendingIDM.active = false; intPendingIDM.active = false;
      swingIDMLevel.active   = false; intIDMLevel.active   = false;

      OB_ResetAll();

      start = maxLen + 1;
      if(InpMaxHistoryBars > 0 && rates_total > InpMaxHistoryBars)
         start = rates_total - InpMaxHistoryBars;
      if(start < maxLen + 1) start = maxLen + 1;
     }
   else
      start = prev_calculated - 1;

   for(int i = start; i < rates_total; i++)
     {
      BufSwingBullBOS[i]   = EMPTY_VALUE;
      BufSwingBullCHoCH[i] = EMPTY_VALUE;
      BufSwingBearBOS[i]   = EMPTY_VALUE;
      BufSwingBearCHoCH[i] = EMPTY_VALUE;
      BufIntBullBOS[i]     = EMPTY_VALUE;
      BufIntBullCHoCH[i]   = EMPTY_VALUE;
      BufIntBearBOS[i]     = EMPTY_VALUE;
      BufIntBearCHoCH[i]   = EMPTY_VALUE;

      ProcessPivots(i, InpSwingLength,    time, high, low, false);
      ProcessPivots(i, InpInternalLength, time, high, low, true);

      // Check post-CBOS IDM levels before structure breaks
      CheckIDMLevel(swingIDMLevel, i, close, time, swingSeqState, swingPendingIDM, false, high, low);
      CheckIDMLevel(intIDMLevel,   i, close, time, intSeqState,   intPendingIDM,   true,  high, low);

      CheckStructureBreaks(i, time, open, close, high, low, false);
      CheckStructureBreaks(i, time, open, close, high, low, true);

      // OB/BB module: extend active zones and check for mitigation (rules 6,7,10)
      UpdateOrderBlocksAndBreakers(i, time, open, high, low, close);

      // Update post-CBOS IDM lines to extend to current bar
      if(swingIDMLevel.active)
         DrawIDMLevel(swingIDMLevel, time[i]);
      if(intIDMLevel.active)
         DrawIDMLevel(intIDMLevel, time[i]);

      if(trailing.valid)
        {
         if(high[i] >= trailing.top)    { trailing.top    = high[i]; trailing.lastTopTime    = time[i]; }
         if(low[i]  <= trailing.bottom) { trailing.bottom = low[i];  trailing.lastBottomTime = time[i]; }
        }

      // PD Array: calculate and draw Premium/Discount levels
      UpdatePDArray(time[i], close[i]);
     }

   if(InpShowStrongWeak && trailing.valid)
      UpdateTrailingLines(time[rates_total-1]);

   return(rates_total);
  }
//+------------------------------------------------------------------+
