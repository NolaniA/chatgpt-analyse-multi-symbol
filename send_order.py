import MetaTrader5 as mt5
import json
from pathlib import Path


class MT5AutoTrader:

    def __init__(self, symbol: str, signal_path: Path = Path(
        "/result_analyse/result_gpt.json"
    )):
        self.symbol = symbol
        self.signal_path = signal_path

    # ==============================
    # MT5 Connection
    # ==============================
    def initialize(self):
        if not mt5.initialize():
            raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")

    def shutdown(self):
        mt5.shutdown()

    # ==============================
    # Load Signal
    # ==============================
    def load_signal(self) -> dict:
        try:
            if not self.signal_path.exists():
                raise FileNotFoundError(f"Signal file not found: {self.signal_path}")

            with open(self.signal_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"load signal error: {e}")
            return {}

    # ==============================
    # Prepare Order Request
    # ==============================
    def build_request(self, signal: dict) -> dict:

        try:

            info = mt5.symbol_info(self.symbol)
            if info is None:
                raise ValueError("Symbol not found")

            if not info.visible:
                mt5.symbol_select(self.symbol, True)

            tick = mt5.symbol_info_tick(self.symbol)
            if tick is None:
                raise RuntimeError("No tick data")

            digits = info.digits
            point = info.point
            stop_level = info.trade_stops_level * point

            type_position = signal["type_position"].lower()
            action = mt5.TRADE_ACTION_DEAL
            order_type = None

            if type_position == "none":
                return

            print(f"type_position: {type_position}")

            # ================= MARKET =================
            if type_position == "buy" or type_position == "BUY":
                order_type = mt5.ORDER_TYPE_BUY
                price = tick.ask

            elif type_position == "sell" or type_position == "SELL":
                order_type = mt5.ORDER_TYPE_SELL
                price = tick.bid

            # ================= PENDING =================
            elif type_position == "buy_stop" or type_position == "BUY_STOP":
                order_type = mt5.ORDER_TYPE_BUY_STOP
                action = mt5.TRADE_ACTION_PENDING
                price = float(signal["price"])
                if price <= tick.ask:
                    raise ValueError("BUY_STOP must be above ASK")

            elif type_position == "sell_stop" or type_position == "SELL_STOP":
                order_type = mt5.ORDER_TYPE_SELL_STOP
                action = mt5.TRADE_ACTION_PENDING
                price = float(signal["price"])
                if price >= tick.bid:
                    raise ValueError("SELL_STOP must be below BID")

            elif type_position == "buy_limit" or type_position == "BUY_LIMIT":
                order_type = mt5.ORDER_TYPE_BUY_LIMIT
                action = mt5.TRADE_ACTION_PENDING
                price = float(signal["price"])
                if price >= tick.ask:
                    raise ValueError("BUY_LIMIT must be below ASK")

            elif type_position == "sell_limit" or type_position == "SELL_LIMIT":
                order_type = mt5.ORDER_TYPE_SELL_LIMIT
                action = mt5.TRADE_ACTION_PENDING
                price = float(signal["price"])
                if price <= tick.bid:
                    raise ValueError("SELL_LIMIT must be above BID")

            else:
                # print("Invalid type_position or type is none")

                # return
                raise ValueError("Invalid type_position or type is none")
        except  Exception as e:
            print(f"build request error: {e}")
            return

        # ===== normalize precision =====
        price = round(float(price), digits)
        sl = round(float(signal["SL"]), digits)
        tp = round(float(signal["TP"]), digits)
        volume = float(signal["lot"])

        # ===== stop distance check =====
        if abs(price - sl) < stop_level:
            raise ValueError("SL too close to price")

        if abs(tp - price) < stop_level:
            raise ValueError("TP too close to price")

        request = {
            "action": action,
            "symbol": self.symbol,
            "volume": volume,
            "type": order_type,
            "price": price,
            "sl": sl,
            "tp": tp,
            "deviation": 30,
            "magic": 999001,
            "comment": "gpt",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,  # ปลอดภัยสุดสำหรับ market
        }

        return request

    # ==============================
    # Send Order
    # ==============================
    def send_order(self, request: dict):

        if request is None:
            return

        filling_modes = [
            mt5.ORDER_FILLING_IOC,
            mt5.ORDER_FILLING_FOK,
            mt5.ORDER_FILLING_RETURN,
        ]
        try:
            for mode in filling_modes:
                request["type_filling"] = mode

                print("Trying filling mode:", mode)
                print("Request:", request)

                result = mt5.order_send(request)

                if result is None:
                    print("order_send returned None:", mt5.last_error())
                    continue

                if result.retcode == mt5.TRADE_RETCODE_DONE:
                    print("Order success")
                    print("Ticket:", result.order)
                    return result

                print("Failed:", result.comment)
        except  Exception as e:
            print(f"All filling modes failed: {e}")
            # raise RuntimeError("All filling modes failed")


    # ==============================
    # Main Run
    # ==============================
    def run(self):
        self.initialize()
        try:
            signal = self.load_signal()
            request = self.build_request(signal)
            self.send_order(request)
        finally:
            self.shutdown()


# ==================================
# Usage
# ==================================
if __name__ == "__main__":
    # SYMBOL = "XAUUSDm"
    # SIGNAL_PATH = Path(
    #     r"C:/Users/Saeng/Documents/GitHub/result_analyse/result_gpt.json"
    # )

    # trader = MT5AutoTrader(SYMBOL, SIGNAL_PATH)
    trader = MT5AutoTrader()
    trader.run()