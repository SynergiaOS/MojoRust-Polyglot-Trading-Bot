import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Button,
  ButtonGroup,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Slider,
  Label,
  Input,
  Alert,
  AlertDescription,
  Badge,
  Separator,
  Switch,
} from '@/components/ui';
import { Play, Pause, Square, RotateCcw, AlertTriangle } from 'lucide-react';
import { useTradingWebSocket } from '@/hooks/useTradingWebSocket';
import { useTradingAPI } from '@/services/tradingAPI';
import { TradingStatus, ExecutionMode, TradingStrategy } from '@/types/trading';

interface TradingControlPanelProps {
  className?: string;
}

export const TradingControlPanel: React.FC<TradingControlPanelProps> = ({
  className,
}) => {
  const { tradingState, sendCommand } = useTradingWebSocket();
  const {
    startTrading,
    stopTrading,
    pauseTrading,
    resumeTrading,
    emergencyStop,
    updateParameters
  } = useTradingAPI();

  const [isStarting, setIsStarting] = useState(false);
  const [isStopping, setIsStopping] = useState(false);
  const [isPausing, setIsPausing] = useState(false);
  const [isResuming, setIsResuming] = useState(false);

  // Form states
  const [selectedStrategy, setSelectedStrategy] = useState<TradingStrategy>(TradingStrategy.ENHANCED_RSI);
  const [executionMode, setExecutionMode] = useState<ExecutionMode>(ExecutionMode.PAPER);
  const [capital, setCapital] = useState(1.0);
  const [maxPositionSize, setMaxPositionSize] = useState(0.1);
  const [maxDrawdown, setMaxDrawdown] = useState(0.15);

  // Get status color
  const getStatusColor = (status: TradingStatus) => {
    switch (status) {
      case TradingStatus.RUNNING:
        return 'bg-green-500';
      case TradingStatus.PAUSED:
        return 'bg-yellow-500';
      case TradingStatus.STOPPED:
        return 'bg-gray-500';
      case TradingStatus.EMERGENCY_STOPPED:
        return 'bg-red-500';
      default:
        return 'bg-gray-500';
    }
  };

  // Get status text
  const getStatusText = (status: TradingStatus) => {
    switch (status) {
      case TradingStatus.RUNNING:
        return 'Running';
      case TradingStatus.PAUSED:
        return 'Paused';
      case TradingStatus.STOPPED:
        return 'Stopped';
      case TradingStatus.STARTING:
        return 'Starting...';
      case TradingStatus.STOPPING:
        return 'Stopping...';
      case TradingStatus.PAUSING:
        return 'Pausing...';
      case TradingStatus.EMERGENCY_STOPPED:
        return 'Emergency Stopped';
      default:
        return 'Unknown';
    }
  };

  const handleStart = async () => {
    if (isStarting) return;

    setIsStarting(true);
    try {
      await startTrading({
        mode: executionMode,
        strategy: selectedStrategy,
        capital: capital,
        max_position_size: maxPositionSize,
        max_drawdown: maxDrawdown,
        cycle_interval: 1.0,
      });
    } catch (error) {
      console.error('Failed to start trading:', error);
    } finally {
      setIsStarting(false);
    }
  };

  const handleStop = async () => {
    if (isStopping) return;

    setIsStopping(true);
    try {
      await stopTrading();
    } catch (error) {
      console.error('Failed to stop trading:', error);
    } finally {
      setIsStopping(false);
    }
  };

  const handlePause = async () => {
    if (isPausing) return;

    setIsPausing(true);
    try {
      await pauseTrading();
    } catch (error) {
      console.error('Failed to pause trading:', error);
    } finally {
      setIsPausing(false);
    }
  };

  const handleResume = async () => {
    if (isResuming) return;

    setIsResuming(true);
    try {
      await resumeTrading();
    } catch (error) {
      console.error('Failed to resume trading:', error);
    } finally {
      setIsResuming(false);
    }
  };

  const handleEmergencyStop = async () => {
    const confirmed = window.confirm(
      'Are you sure you want to trigger an emergency stop? This will halt all trading immediately.'
    );

    if (confirmed) {
      try {
        await emergencyStop();
      } catch (error) {
        console.error('Failed to trigger emergency stop:', error);
      }
    }
  };

  const handleParameterUpdate = async () => {
    try {
      await updateParameters({
        max_position_size: maxPositionSize,
        max_drawdown: maxDrawdown,
        cycle_interval: 1.0,
      });
    } catch (error) {
      console.error('Failed to update parameters:', error);
    }
  };

  const canStart = tradingState.status === TradingStatus.STOPPED ||
                   tradingState.status === TradingStatus.EMERGENCY_STOPPED;
  const canStop = tradingState.status === TradingStatus.RUNNING ||
                  tradingState.status === TradingStatus.PAUSED;
  const canPause = tradingState.status === TradingStatus.RUNNING;
  const canResume = tradingState.status === TradingStatus.PAUSED;

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Status Card */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            Trading Status
            <div className="flex items-center space-x-2">
              <div className={`w-3 h-3 rounded-full ${getStatusColor(tradingState.status)}`} />
              <span className="text-sm font-medium">
                {getStatusText(tradingState.status)}
              </span>
            </div>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div>
              <Label className="text-sm font-medium">Portfolio Value</Label>
              <p className="text-2xl font-bold">
                {tradingState.metrics?.portfolio_value?.toFixed(4) || '0.0000'} SOL
              </p>
            </div>
            <div>
              <Label className="text-sm font-medium">Daily P&L</Label>
              <p className={`text-2xl font-bold ${
                (tradingState.metrics?.daily_pnl || 0) >= 0 ? 'text-green-600' : 'text-red-600'
              }`}>
                {(tradingState.metrics?.daily_pnl || 0) >= 0 ? '+' : ''}
                {tradingState.metrics?.daily_pnl?.toFixed(4) || '0.0000'} SOL
              </p>
            </div>
            <div>
              <Label className="text-sm font-medium">Total Trades</Label>
              <p className="text-2xl font-bold">
                {tradingState.metrics?.total_trades || 0}
              </p>
            </div>
            <div>
              <Label className="text-sm font-medium">Win Rate</Label>
              <p className="text-2xl font-bold">
                {((tradingState.metrics?.win_rate || 0) * 100).toFixed(1)}%
              </p>
            </div>
          </div>

          {tradingState.status === TradingStatus.EMERGENCY_STOPPED && (
            <Alert className="mt-4 border-red-200 bg-red-50">
              <AlertTriangle className="h-4 w-4 text-red-600" />
              <AlertDescription className="text-red-800">
                Emergency stop is active. Trading is halted until manually resumed.
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      {/* Control Buttons */}
      <Card>
        <CardHeader>
          <CardTitle>Trading Controls</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            <Button
              onClick={handleStart}
              disabled={!canStart || isStarting}
              className="flex items-center space-x-2"
            >
              <Play className="w-4 h-4" />
              <span>{isStarting ? 'Starting...' : 'Start'}</span>
            </Button>

            <Button
              onClick={handleStop}
              disabled={!canStop || isStopping}
              variant="outline"
              className="flex items-center space-x-2"
            >
              <Square className="w-4 h-4" />
              <span>{isStopping ? 'Stopping...' : 'Stop'}</span>
            </Button>

            <Button
              onClick={handlePause}
              disabled={!canPause || isPausing}
              variant="outline"
              className="flex items-center space-x-2"
            >
              <Pause className="w-4 h-4" />
              <span>{isPausing ? 'Pausing...' : 'Pause'}</span>
            </Button>

            <Button
              onClick={handleResume}
              disabled={!canResume || isResuming}
              variant="outline"
              className="flex items-center space-x-2"
            >
              <RotateCcw className="w-4 h-4" />
              <span>{isResuming ? 'Resuming...' : 'Resume'}</span>
            </Button>

            <Separator orientation="vertical" className="mx-2" />

            <Button
              onClick={handleEmergencyStop}
              variant="destructive"
              className="flex items-center space-x-2"
            >
              <AlertTriangle className="w-4 h-4" />
              <span>Emergency Stop</span>
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Configuration */}
      <Card>
        <CardHeader>
          <CardTitle>Trading Configuration</CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Strategy Selection */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <Label htmlFor="strategy">Strategy</Label>
              <Select
                value={selectedStrategy}
                onValueChange={(value: TradingStrategy) => setSelectedStrategy(value)}
                disabled={tradingState.status === TradingStatus.RUNNING}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select strategy" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={TradingStrategy.ENHANCED_RSI}>
                    Enhanced RSI
                  </SelectItem>
                  <SelectItem value={TradingStrategy.MOMENTUM}>
                    Momentum
                  </SelectItem>
                  <SelectItem value={TradingStrategy.MEAN_REVERSION}>
                    Mean Reversion
                  </SelectItem>
                  <SelectItem value={TradingStrategy.ARBITRAGE}>
                    Arbitrage
                  </SelectItem>
                  <SelectItem value={TradingStrategy.FLASH_LOAN}>
                    Flash Loan
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div>
              <Label htmlFor="mode">Execution Mode</Label>
              <Select
                value={executionMode}
                onValueChange={(value: ExecutionMode) => setExecutionMode(value)}
                disabled={tradingState.status === TradingStatus.RUNNING}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select mode" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ExecutionMode.PAPER}>
                    Paper Trading
                  </SelectItem>
                  <SelectItem value={ExecutionMode.LIVE}>
                    Live Trading
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Capital and Risk Parameters */}
          <div className="space-y-4">
            <div>
              <Label htmlFor="capital">Initial Capital (SOL)</Label>
              <Input
                id="capital"
                type="number"
                step="0.01"
                min="0.01"
                max="1000"
                value={capital}
                onChange={(e) => setCapital(parseFloat(e.target.value) || 0)}
                disabled={tradingState.status === TradingStatus.RUNNING}
              />
            </div>

            <div>
              <Label htmlFor="maxPositionSize">
                Max Position Size: {((maxPositionSize) * 100).toFixed(1)}%
              </Label>
              <Slider
                id="maxPositionSize"
                min={0.01}
                max={0.5}
                step={0.01}
                value={[maxPositionSize]}
                onValueChange={([value]) => setMaxPositionSize(value)}
                disabled={tradingState.status === TradingStatus.RUNNING}
                className="mt-2"
              />
            </div>

            <div>
              <Label htmlFor="maxDrawdown">
                Max Drawdown: {((maxDrawdown) * 100).toFixed(1)}%
              </Label>
              <Slider
                id="maxDrawdown"
                min={0.05}
                max={0.5}
                step={0.01}
                value={[maxDrawdown]}
                onValueChange={([value]) => setMaxDrawdown(value)}
                disabled={tradingState.status === TradingStatus.RUNNING}
                className="mt-2"
              />
            </div>
          </div>

          <Button
            onClick={handleParameterUpdate}
            disabled={tradingState.status === TradingStatus.RUNNING}
            variant="outline"
          >
            Update Parameters
          </Button>
        </CardContent>
      </Card>

      {/* Active Strategy Info */}
      {tradingState.config && (
        <Card>
          <CardHeader>
            <CardTitle>Active Strategy Information</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <Label className="text-sm font-medium">Current Strategy</Label>
                <p className="text-lg font-semibold capitalize">
                  {tradingState.config.strategy?.replace('_', ' ')}
                </p>
              </div>
              <div>
                <Label className="text-sm font-medium">Execution Mode</Label>
                <Badge variant={tradingState.config.mode === 'live' ? 'destructive' : 'secondary'}>
                  {tradingState.config.mode?.toUpperCase()}
                </Badge>
              </div>
              <div>
                <Label className="text-sm font-medium">Max Position Size</Label>
                <p className="text-lg font-semibold">
                  {((tradingState.config.max_position_size || 0) * 100).toFixed(1)}%
                </p>
              </div>
              <div>
                <Label className="text-sm font-medium">Max Drawdown</Label>
                <p className="text-lg font-semibold">
                  {((tradingState.config.max_drawdown || 0) * 100).toFixed(1)}%
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
};