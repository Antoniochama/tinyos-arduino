#include "Atm328pUsartConfig.h"

module HplAtm328pUsartP
{
  provides
  {
    interface Init;
    interface StdControl as RxControl;
    interface StdControl as TxControl;
    interface Atm328pUsart as Usart;
  }
  uses interface HplAtm328pUsartConfig as Config;
}
implementation
{
  // NOTE: need to always write FE0/DOR0/UPE0 to zero when writing to UCSR0A
  enum { UCSR0A_WMASK = ((1 << FE0) | (1 << DOR0) | (1 << UPE0)) };

  command error_t Init.init ()
  {
    atm328p_usart_config_t *cfg = call Config.getConfig ();
    if (!cfg)
      return FAIL;

    atomic
    {
      uint16_t ubrr;
      uint8_t ubrr_div;

      // Note: we don't even pretend to know about multi-processor comm mode
      // and always disable it. Someone who can actually test it is welcome to
      // add support for it...
      if (cfg->mode == ATM328P_USART_ASYNC && cfg->double_speed)
        UCSR0A = (1 << U2X0);
      else
        UCSR0A = 0;

      UCSR0B |= ((cfg->bits & 0x04) >> 2) << UCSZ02;

      UCSR0C =
        (cfg->mode << UMSEL00) |
        (cfg->parity << UPM00) |
        (cfg->two_stop_bits ? (1 << USBS0) : 0) |
        ((cfg->bits & 0x03) << UCSZ00) |           // top bit is in UCSR0B
        (cfg->polarity_rising_edge << UCPOL0);

      if (cfg->mode == ATM328P_USART_ASYNC)
        ubrr_div = cfg->double_speed ? 8 : 16;
      else
        ubrr_div = 2;

      // we very much care about rounding correctly, truncating would be bad
      ubrr = (uint16_t)((float)(F_CPU / ubrr_div) / cfg->baud - 1 + 0.5);

      UBRR0 = (ubrr & 0x0fff);
    }

    return SUCCESS;
  }

  // TODO: power state handling
  command error_t RxControl.start ()
  {
    UCSR0B |= (1 << RXEN0);
    return SUCCESS;
  }

  command error_t RxControl.stop ()
  {
    UCSR0B &= ~(1 << RXEN0);
    return SUCCESS;
  }

  command error_t TxControl.start ()
  {
    UCSR0B |= (1 << TXEN0);
    return SUCCESS;
  }

  command error_t TxControl.stop ()
  {
    UCSR0B &= ~(1 << TXEN0);
    return SUCCESS;
  }

  async command void Usart.enableRxcInterrupt ()
  {
    UCSR0B |= (1 << RXCIE0);
  }

  async command void Usart.disableRxcInterrupt ()
  {
    UCSR0B &= ~(1 << RXCIE0);
  }

  async command void Usart.enableTxcInterrupt ()
  {
    UCSR0B |= (1 << TXCIE0);
  }

  async command void Usart.disableTxcInterrupt ()
  {
    UCSR0B &= ~(1 << TXCIE0);
  }

  async command void Usart.enableDreInterrupt ()
  {
    UCSR0B |= (1 << UDRIE0);
  }

  async command void Usart.disableDreInterrupt ()
  {
    UCSR0B &= ~(1 << UDRIE0);
  }

  async command bool Usart.rxComplete ()
  {
    return (UCSR0A & (1 << RXC0));
  }

  async command bool Usart.txComplete ()
  {
    return (UCSR0A & (1 << TXC0));
  }

  async command bool Usart.txEmpty ()
  {
    return (UCSR0A & (1 << UDRE0));
  }

  async command bool Usart.frameError ()
  {
    return (UCSR0A & (1 << FE0));
  }

  async command bool Usart.dataOverrun ()
  {
    return (UCSR0A & (1 << DOR0));
  }

  async command bool Usart.parityError ()
  {
    return (UCSR0A & (1 << UPE0));
  }

  async command bool Usart.rxBit8 ()
  {
    return (UCSR0B & (1 << RXB80));
  }

  async command uint8_t Usart.rx ()
  {
    return UDR0;
  }

  async command void Usart.txBit8 ()
  {
    UCSR0B |= (1 << TXB80);
  }

  async command void Usart.tx (uint8_t data)
  {
    atomic
    {
      UCSR0A = (UCSR0A & UCSR0A_WMASK) | (1 << TXC0);
      UDR0 = data;
    }
  }

  AVR_NONATOMIC_HANDLER(USART_RX_vect)
  {
    signal Usart.rxDone ();
  }

  AVR_NONATOMIC_HANDLER(USART_UDRE_vect)
  {
    signal Usart.txEmpty ();
  }

  AVR_NONATOMIC_HANDLER(USART_TX_vect)
  {
    signal Usart.txDone ();
  }

}
