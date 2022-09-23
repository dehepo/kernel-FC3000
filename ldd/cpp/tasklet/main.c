#include <linux/init.h>
#include <linux/device.h>
#include <linux/module.h>
#include <linux/delay.h>
#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/mm.h>
#include <linux/gpio.h>
#include <linux/interrupt.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Steward Fu");
MODULE_DESCRIPTION("Linux Driver");
 
#define BUTTON 27

struct tasklet_struct mytask={0};

void tasklet_handler(unsigned long data)
{
  printk("%s\n", __func__);
}

static irqreturn_t irq_handler(int irq, void *arg)
{
  tasklet_schedule(&mytask);
  return IRQ_HANDLED;
}

int ldd_init(void)
{
  tasklet_init(&mytask, tasklet_handler, 0);
  request_irq(gpio_to_irq(BUTTON), irq_handler, IRQF_TRIGGER_RISING, "gpio_irq", NULL);
  return 0;
}
 
void ldd_exit(void)
{
  free_irq(gpio_to_irq(BUTTON), NULL);
  tasklet_kill(&mytask);
}
 
module_init(ldd_init);
module_exit(ldd_exit);

