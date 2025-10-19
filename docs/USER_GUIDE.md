# 🎮 MojoRust Trading Control System - User Guide

## Overview

The MojoRust Trading Control System provides comprehensive real-time control and monitoring of your algorithmic trading bot. This guide will help you understand and use all the features effectively.

## 🚀 Quick Start

### 1. **Start the Control System**

```bash
# Start the Trading Control API
cd /home/marcin/Projects/MojoRust
python src/api/trading_control_api.py

# Start the web dashboard (in another terminal)
cd dashboard
npm start
```

### 2. **Access the Interface**

- **Web Dashboard**: http://localhost:3000
- **API Documentation**: http://localhost:8083/docs
- **WebSocket**: ws://localhost:8083/ws/trading

## 📊 Web Dashboard Features

### Trading Control Panel

The main control panel gives you complete control over your trading bot:

#### **Status Indicators**
- **Portfolio Value**: Real-time portfolio valuation in SOL
- **Daily P&L**: Today's profit/loss with color coding
- **Total Trades**: Number of trades executed
- **Win Rate**: Success rate percentage

#### **Control Buttons**
- **Start**: Begin trading with selected strategy and parameters
- **Stop**: Gracefully stop all trading activity
- **Pause**: Temporarily pause trading (keeps positions open)
- **Resume**: Resume paused trading
- **Emergency Stop**: Immediately halt all trading activity

#### **Configuration Options**
- **Strategy Selection**: Choose from available trading strategies
- **Execution Mode**: Paper trading (practice) or Live trading
- **Initial Capital**: Set starting capital amount
- **Risk Parameters**: Adjust position size and drawdown limits

### Manual Token Targeting

Add specific tokens you want the bot to monitor and trade:

#### **Adding Tokens**
1. Go to the "Manual Targeting" section
2. Enter the **token address** (Solana contract address)
3. Set parameters:
   - **Priority**: How urgently to monitor this token
   - **Max Buy Amount**: Maximum SOL to spend
   - **Target ROI**: Desired profit margin
   - **Stop Loss**: Automatic exit point
   - **Confidence Threshold**: Minimum confidence for trading

#### **Token Status Monitoring**
- **Watching**: Token is being monitored
- **Analyzing**: Bot is evaluating trading opportunity
- **Trading**: Active position in this token
- **Completed**: Trading cycle finished

#### **Manual Trading**
Click "Buy" or "Sell" next to any watched token to execute manual trades.

### Portfolio Management

View and manage your current positions:

#### **Position Details**
- **Token Address**: Contract address
- **Amount**: Number of tokens held
- **Average Price**: Entry price
- **Current Price**: Real-time market price
- **Unrealized P&L**: Profit/loss on open positions
- **Duration**: How long position has been open

#### **Actions**
- **Close Position**: Sell entire position
- **Partial Close**: Sell portion of position
- **Set Stop Loss**: Adjust stop loss level
- **Set Take Profit**: Set profit target

### Risk Management

Monitor and control trading risks:

#### **Risk Metrics**
- **Current Drawdown**: Portfolio decline from peak
- **Daily Loss**: Today's loss amount
- **Portfolio Risk**: Total risk exposure
- **Position Concentration**: Risk from position sizes
- **Correlation Risk**: Risk from similar positions

#### **Alerts**
- **Risk Warnings**: When metrics exceed thresholds
- **Intervention Alerts**: Automatic risk management actions
- **System Alerts**: Technical issues or errors

#### **Risk Controls**
- **Adjust Limits**: Change risk thresholds
- **Emergency Stop**: Immediate trading halt
- **Risk Interventions**: View automatic interventions

## 🛠️ API Usage

### REST API Endpoints

#### Trading Control
```bash
# Start trading
curl -X POST http://localhost:8083/api/trading/start \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "paper",
    "strategy": "enhanced_rsi",
    "capital": 1.0,
    "max_position_size": 0.1
  }'

# Get trading status
curl http://localhost:8083/api/trading/status

# Stop trading
curl -X POST http://localhost:8083/api/trading/stop

# Emergency stop
curl -X POST http://localhost:8083/api/trading/emergency/stop
```

#### Manual Targeting
```bash
# Add token to watchlist
curl -X POST http://localhost:8083/api/targeting/add \
  -H "Content-Type: application/json" \
  -d '{
    "token_address": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    "token_symbol": "USDC",
    "priority": "high",
    "max_buy_amount_sol": 0.5,
    "target_roi": 0.2,
    "notes": "Stablecoin arbitrage opportunity"
  }'

# Get watchlist
curl http://localhost:8083/api/targeting/watchlist

# Execute manual trade
curl -X POST http://localhost:8083/api/targeting/execute \
  -H "Content-Type: application/json" \
  -d '{
    "token_address": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    "action": "buy",
    "amount_sol": 0.1,
    "force_execution": false
  }'
```

### WebSocket Real-time Updates

Connect to the WebSocket for live updates:

```javascript
const ws = new WebSocket('ws://localhost:8083/ws/trading');

ws.onmessage = function(event) {
    const data = JSON.parse(event.data);

    switch(data.type) {
        case 'status_update':
            console.log('Trading status:', data.status);
            break;
        case 'portfolio_update':
            console.log('Portfolio value:', data.portfolio_value);
            break;
        case 'trade_executed':
            console.log('New trade:', data.trade);
            break;
        case 'risk_alert':
            console.log('Risk alert:', data.alert);
            break;
    }
};
```

## 📱 Mobile Access

The web dashboard is fully responsive and works on mobile devices:

- **Touch-optimized controls** for easy trading on the go
- **Real-time updates** even on mobile networks
- **Emergency stop** button always accessible
- **Push notifications** (if enabled in browser)

## ⚙️ Configuration

### Trading Strategies

Choose from pre-configured strategies:

1. **Enhanced RSI**: Uses RSI indicators with support/resistance
2. **Momentum**: Follows market momentum and volume
3. **Mean Reversion**: Bets on price returning to average
4. **Arbitrage**: Exploits price differences across exchanges
5. **Flash Loan**: Uses flash loans for arbitrage opportunities

### Risk Parameters

Configure risk management:

- **Max Position Size**: Maximum % of portfolio per trade (1-50%)
- **Max Drawdown**: Maximum portfolio decline allowed (5-50%)
- **Daily Trade Limit**: Maximum trades per day (1-100)
- **Confidence Threshold**: Minimum confidence for trades (10-100%)

### Manual Targeting Settings

Customize token monitoring:

- **Priority Levels**: Low, Medium, High, Critical
- **Expiration**: Auto-remove tokens after specified time
- **Custom Parameters**: Individual settings per token

## 🚨 Emergency Procedures

### Emergency Stop

If you need to immediately halt all trading:

1. **Web Dashboard**: Click the red "Emergency Stop" button
2. **API**: Send POST to `/api/trading/emergency/stop`
3. **Command Line**: Use the emergency stop script

### Recovery After Emergency Stop

1. **Review**: Check why emergency stop was triggered
2. **Resolve**: Fix any underlying issues
3. **Configure**: Adjust risk parameters if needed
4. **Restart**: Start trading with new parameters

## 📈 Performance Monitoring

### Key Metrics

Monitor these metrics regularly:

- **Win Rate**: Percentage of profitable trades
- **Average Trade P&L**: Average profit/loss per trade
- **Maximum Drawdown**: Largest portfolio decline
- **Sharpe Ratio**: Risk-adjusted returns
- **Profit Factor**: Total profits / Total losses

### Performance Reports

Generate detailed reports:

```bash
# Get daily performance
curl http://localhost:8083/api/trading/performance/daily

# Get strategy comparison
curl http://localhost:8083/api/trading/performance/strategies

# Get risk analysis
curl http://localhost:8083/api/risk/analysis
```

## 🔧 Troubleshooting

### Common Issues

#### **Trading Won't Start**
- Check if parameters are within valid ranges
- Ensure sufficient capital is allocated
- Verify API connections are working
- Check system logs for errors

#### **WebSocket Connection Issues**
- Refresh the dashboard page
- Check network connection
- Verify API server is running
- Try different browser

#### **Manual Trades Not Executing**
- Check if token is in watchlist
- Verify sufficient funds available
- Ensure risk parameters allow the trade
- Check token analysis status

#### **High Risk Alerts**
- Review current positions
- Check market volatility
- Consider reducing position sizes
- Evaluate stop-loss levels

### Getting Help

1. **Check Logs**: Review system and API logs
2. **Monitor Dashboard**: Look for error messages
3. **Review Configuration**: Verify all settings
4. **Contact Support**: Reach out for technical assistance

## 🔒 Security Best Practices

### API Security

- Use HTTPS in production environments
- Implement API key authentication
- Set up rate limiting
- Monitor for unauthorized access

### Trading Security

- Start with paper trading mode
- Use small position sizes initially
- Set conservative risk limits
- Monitor all automated interventions

### Data Protection

- Never share API keys
- Use secure connections (WSS for WebSocket)
- Regularly update passwords
- Backup important configurations

## 📚 Advanced Features

### Custom Strategies

Create and deploy custom trading strategies:

1. Develop strategy logic in Python/Mojo
2. Test with historical data
3. Deploy to the trading system
4. Monitor performance in real-time

### Automated Interventions

Configure automatic risk management:

- **Position Size Reduction**: Automatically reduce sizes when risk increases
- **Profit Taking**: Auto-close positions at profit targets
- **Stop Loss**: Automatic exit at loss thresholds
- **Correlation Management**: Reduce exposure to correlated assets

### Multi-Token Monitoring

Monitor multiple tokens simultaneously:

- **Batch Operations**: Add multiple tokens at once
- **Priority Queuing**: High-priority tokens analyzed first
- **Resource Management**: Limit concurrent analysis
- **Performance Tracking**: Track individual token performance

## 🎯 Best Practices

### Daily Operations

1. **Morning Check**: Review overnight performance
2. **Risk Assessment**: Check current risk levels
3. **Position Review**: Evaluate open positions
4. **Strategy Performance**: Compare strategy results
5. **Market Analysis**: Stay informed about market conditions

### Weekly Reviews

1. **Performance Analysis**: Review weekly returns
2. **Risk Metrics**: Evaluate risk management effectiveness
3. **Strategy Optimization**: Adjust strategy parameters
4. **Token Review**: Clean up watchlist
5. **System Health**: Check all systems functioning

### Monthly Optimization

1. **Strategy Rotation**: Consider switching strategies
2. **Parameter Tuning**: Optimize trading parameters
3. **Risk Adjustments**: Update risk limits
4. **Performance Benchmarking**: Compare against benchmarks
5. **System Updates**: Apply any available updates

---

For additional support or questions, refer to the technical documentation or contact the development team.