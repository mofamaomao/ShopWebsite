import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getCart, addToCart as addToCartApi, updateCartItem as updateApi, removeCartItem as removeApi } from '@/api/cart'

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
    await fetchCount()
  }

  async function updateItem(productId, quantity) {
    await updateApi(productId, quantity)
    await fetchCount()
  }

  async function removeItem(productId) {
    await removeApi(productId)
    await fetchCount()
  }

  function clearCart() {
    cartCount.value = 0
  }

  return { cartCount, fetchCount, addItem, updateItem, removeItem, clearCart }
})
