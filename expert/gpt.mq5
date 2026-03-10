//+------------------------------------------------------------------+
//|                                                          gpt.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;


input double PercentTrailing         = 80;
input double StartPercentTrailing    = 40;
input int    OrderHold               = 1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   //--- check market open
   if(!MarketOpen())
      return INIT_FAILED;
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   //---CHECK DATE TIME TRADE
   if(!IsTradingSession())
      return;
      
   TrailingStop();
  }
//+------------------------------------------------------------------+


void  TrailingStop(double StopLoss = 200)
  {
   
   double percentag_trailing       = PercentTrailing / 100;
   double percentag_start_trailing = StartPercentTrailing / 100;
   
   //double trailing_stop = Trailing * _Point; 

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong  ticket        = PositionGetTicket(i);
      string ticket_symbol = PositionGetSymbol(i);
      double price_ask     = SymbolInfoDouble(ticket_symbol, SYMBOL_ASK);
      double price_bid     = SymbolInfoDouble(ticket_symbol, SYMBOL_BID);
      double Spread        = (price_ask-price_bid);
      
      //---focus position
      PositionSelectByTicket(ticket);
      

      double stop_loss   = PositionGetDouble(POSITION_SL);
      double take_profit = PositionGetDouble(POSITION_TP);

      double price_open_position    = PositionGetDouble(POSITION_PRICE_OPEN);
      double price_open_spread_buy  = price_open_position + (Spread * 2);
      double price_open_spread_sell = price_open_position - (Spread * 2);
      

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {

            double tp_distance            = take_profit - price_open_position;
            double price_percentage       = price_open_position + percentag_trailing * tp_distance;
            double price_start_percentage = price_open_position + percentag_start_trailing * tp_distance;
            // distance sl
            double   sl_distance          = take_profit - price_bid;
            
            if (stop_loss == 0 && StopLoss != 0)   // auto set sl
            {
               
               trade.PositionModify(ticket, price_bid - StopLoss*_Point, take_profit);
               
            }
            else if (price_bid > price_start_percentage && price_open_position > stop_loss) // set sl block 
            {
               trade.PositionModify(ticket, price_open_spread_buy, take_profit);
            }
            else if (price_bid > price_percentage && (price_bid - stop_loss) > sl_distance)   // trailing

            {
               
               double new_stop_loss = price_bid - sl_distance;
               trade.PositionModify(ticket, new_stop_loss, take_profit);
            }
            

         }
         else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
         
            double tp_distance            = price_open_position - take_profit;
            double price_percentage       = price_open_position - percentag_trailing * tp_distance;
            double price_start_percentage = price_open_position - percentag_start_trailing * tp_distance;
            // distance sl
            double   sl_distance          = price_ask - take_profit;
         
            
            if(stop_loss == 0 && StopLoss != 0)   // auto set sl+
            {
               trade.PositionModify(ticket, price_ask + StopLoss*_Point, take_profit);
            }
            else if (price_ask < price_start_percentage && price_open_position < stop_loss) // set sl block 
            {
               trade.PositionModify(ticket, price_open_spread_sell, take_profit);
            }
            else if (price_ask < price_percentage && (stop_loss - price_ask) > sl_distance)   // trailing 

            {
               double new_stop_loss = price_ask + sl_distance;
               trade.PositionModify(ticket, new_stop_loss, take_profit);
            }
            
            
         }
      
     }
  }
bool IsTradingSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeLocal(), dt);

    // วันในสัปดาห์: 1=จันทร์, ... 5=ศุกร์
    if (dt.day_of_week == 0 || dt.day_of_week == 6) // อาทิตย์/เสาร์ ห้ามเทรด
        return false;

    // ถ้าเป็นวันจันทร์ 0:00-1:59 (คืนอาทิตย์) ไม่ให้เทรด
    if (dt.day_of_week == 1 && dt.hour < 2)
        return false;

    // 07:00-23:59 ของจันทร์-ศุกร์ เทรดได้
    if (dt.hour >= 5)
        return true;

    // 00:00-01:59 ของอังคาร-ศุกร์ เทรดได้
    if (dt.hour < 2)
        return true;

    // นอกนั้นไม่เทรด
    return false;
}


void CheckAndDeleteOldestPending()
{
    int total_orders = OrdersTotal();
    if (total_orders <= OrderHold)
        return;

    ulong oldest_ticket = 0;
    datetime oldest_time = LONG_MAX;

    for (int i = total_orders - 1; i >= 0; i--) 
    {
        ulong ticket = OrderGetTicket(i);
        if (ticket == 0) continue; 

        if (!OrderSelect(ticket))
            continue;

        int type = (int)OrderGetInteger(ORDER_TYPE);
        if (type != ORDER_TYPE_BUY_LIMIT &&
            type != ORDER_TYPE_SELL_LIMIT &&
            type != ORDER_TYPE_BUY_STOP &&
            type != ORDER_TYPE_SELL_STOP)
            continue; 

        datetime setup_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
        if (setup_time < oldest_time)
        {
            oldest_time = setup_time;
            oldest_ticket = ticket;
        }
    }

    if (oldest_ticket > 0)
    {
        if (!trade.OrderDelete(oldest_ticket))
        {
            Print("❌ Delete Pending Order Fail Ticket: ", oldest_ticket, " | Error: ", GetLastError());
        }
        else
        {
            Print("✅ Delete Pending Success Ticket: ", oldest_ticket,
                  " | Time setup", TimeToString(oldest_time, TIME_DATE | TIME_MINUTES));
        }
    }
}

bool MarketOpen(string symbol = NULL)
{
   if (symbol == NULL || symbol == "")
      symbol = _Symbol;
   return   SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED;
}