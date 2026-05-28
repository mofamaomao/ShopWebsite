import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getCart, addToCart as addToCartApi } from '@/api/cart'

export const useCartStore = defineStore('cart', () => {
  const cartCount = ref(0)

  async function fetchCount() {
    try {
      const data = await getCart()
      cartCount.value = data.items?.reduce((sum, item) => sum + item.quantity, 0) ?? 0
    } catch {
      cartCount.value = 0
    }
  }

  async function addItem(productId, qty) {
    await addToCartApi({ productId, quantity: qty })
    cartCount.value += qty
  }

  return { cartCount, fetchCount, addItem }
})
