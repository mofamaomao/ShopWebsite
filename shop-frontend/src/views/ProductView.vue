<template>
  <div class="product-page">
    <!-- 返回导航 -->
    <div class="page-nav">
      <el-button text @click="$router.back()">
        <el-icon style="margin-right:4px"><ArrowLeft /></el-icon>返回
      </el-button>
    </div>

    <div v-loading="loading" class="product-detail">
      <template v-if="product">
        <!-- 商品图 -->
        <div class="product-img-wrap">
          <el-image
            v-if="product.imageUrl"
            :src="product.imageUrl"
            fit="cover"
            style="width:100%;height:100%"
          />
          <el-icon v-else size="80" color="#c0c4cc"><Picture /></el-icon>
        </div>

        <!-- 商品信息 -->
        <div class="product-meta">
          <h1>{{ product.name }}</h1>
          <div class="price">¥{{ product.price }}</div>

          <div v-if="stockStatus" :class="['stock-status', stockStatus.cls]">
            {{ stockStatus.text }}
          </div>

          <div v-if="product.description" class="desc">{{ product.description }}</div>

          <div class="actions" v-if="product.stock > 0">
            <el-input-number
              v-model="qty"
              :min="1"
              :max="product.stock"
              size="default"
            />
            <el-button
              type="primary"
              size="large"
              :loading="adding"
              @click="handleAddCart"
            >加入购物车</el-button>
          </div>
          <div v-else class="sold-out-actions">
            <el-button size="large" disabled>已售罄</el-button>
          </div>
        </div>
      </template>

      <el-empty
        v-else-if="!loading"
        :description="errorMsg || '商品不存在'"
      >
        <el-button v-if="errorMsg" type="primary" @click="retry">重新加载</el-button>
        <el-button v-else @click="$router.push('/')">返回首页</el-button>
      </el-empty>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Picture, ArrowLeft } from '@element-plus/icons-vue'
import { getProduct } from '@/api/product'
import { useUserStore } from '@/stores/user'
import { useCartStore } from '@/stores/cart'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const cartStore = useCartStore()
const product = ref(null)
const loading = ref(false)
const adding = ref(false)
const qty = ref(1)
const errorMsg = ref('')

const stockStatus = computed(() => {
  if (!product.value) return null
  const s = product.value.stock
  if (s === 0) return null  // handled separately via v-if product.stock > 0
  if (s <= 10) return { text: `仅剩 ${s} 件`, cls: 'low-stock' }
  return null
})

async function load() {
  loading.value = true
  errorMsg.value = ''
  try {
    product.value = await getProduct(route.params.id)
  } catch (err) {
    if (err.code === 404 || err.message?.includes('不存在')) {
      product.value = null
    } else {
      errorMsg.value = err.message || '加载失败，请重试'
    }
  } finally {
    loading.value = false
  }
}

function retry() { load() }

onMounted(load)

async function handleAddCart() {
  if (adding.value) return
  if (!userStore.isLoggedIn) {
    ElMessage.warning('请先登录')
    router.push('/login')
    return
  }
  if (qty.value > product.value.stock) {
    ElMessage.warning(`数量不能超过库存（${product.value.stock} 件）`)
    qty.value = product.value.stock
    return
  }
  adding.value = true
  try {
    await cartStore.addItem(product.value.id, qty.value)
    ElMessage.success('已加入购物车')
  } catch (err) {
    ElMessage.error(err.message || '操作失败')
  } finally {
    adding.value = false
  }
}
</script>

<style scoped>
.product-page {
  max-width: 900px;
  margin: 24px auto;
  padding: 0 16px;
}

.page-nav {
  margin-bottom: 16px;
}

.product-detail {
  display: flex;
  gap: 40px;
  background: #fff;
  padding: 32px;
  border-radius: 8px;
  min-height: 300px;
  border: 1px solid var(--color-border-light);
}

.product-img-wrap {
  width: 320px;
  aspect-ratio: 1;
  background: oklch(0.975 0.004 353deg);
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  flex-shrink: 0;
  overflow: hidden;
}

.product-meta {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.product-meta h1 {
  font-size: 22px;
  font-weight: 600;
  color: var(--color-ink);
  line-height: 1.4;
  text-wrap: balance;
}

.price {
  color: var(--color-price);
  font-size: 32px;
  font-weight: 700;
  letter-spacing: -0.5px;
}

.stock-status {
  display: inline-block;
  font-size: 13px;
  font-weight: 500;
  padding: 3px 10px;
  border-radius: 4px;
  align-self: flex-start;
}
.low-stock {
  background: oklch(0.97 0.04 60deg);
  color: var(--color-warning);
}

.desc {
  color: var(--color-muted);
  line-height: 1.65;
  font-size: 14px;
  text-wrap: pretty;
}

.actions {
  display: flex;
  gap: 16px;
  align-items: center;
  margin-top: auto;
}

.sold-out-actions {
  margin-top: auto;
}

/* 移动端：垂直堆叠 */
@media (max-width: 640px) {
  .product-detail {
    flex-direction: column;
    gap: 20px;
    padding: 20px;
  }
  .product-img-wrap {
    width: 100%;
  }
  .actions {
    flex-wrap: wrap;
  }
}
</style>
