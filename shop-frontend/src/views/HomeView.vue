<template>
  <div class="home-page">
    <div class="filter-bar">共 {{ total }} 件商品</div>
    <div v-loading="loading" class="product-grid">
      <el-card
        v-for="p in filteredList"
        :key="p.id"
        class="product-card"
        shadow="hover"
        @click="$router.push(`/product/${p.id}`)"
      >
        <div class="product-img">
          <el-icon size="60" color="#c0c4cc"><Picture /></el-icon>
        </div>
        <div class="product-name">{{ p.name }}</div>
        <div class="product-price">¥{{ p.price }}</div>
        <div class="product-stock">库存：{{ p.stock }}</div>
      </el-card>
      <el-empty v-if="!loading && filteredList.length === 0" description="没有找到商品" style="grid-column:1/-1" />
    </div>
    <el-pagination
      v-if="total > pageSize"
      layout="prev, pager, next"
      :total="total"
      :page-size="pageSize"
      :current-page="pageNum"
      @current-change="handlePageChange"
      class="pagination"
    />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Picture } from '@element-plus/icons-vue'
import { getProducts } from '@/api/product'

const route = useRoute()
const loading = ref(false)
const list = ref([])
const total = ref(0)
const pageNum = ref(1)
const pageSize = ref(8)

const filteredList = computed(() => {
  const kw = route.query.keyword?.toLowerCase()
  if (!kw) return list.value
  return list.value.filter(p => p.name.toLowerCase().includes(kw))
})

async function fetchList() {
  loading.value = true
  try {
    const data = await getProducts({ pageNum: pageNum.value, pageSize: pageSize.value })
    list.value = data.list || []
    total.value = data.total || 0
  } finally {
    loading.value = false
  }
}

function handlePageChange(page) {
  pageNum.value = page
  fetchList()
}

onMounted(fetchList)
watch(() => route.query.keyword, fetchList)
</script>

<style scoped>
.home-page {
  max-width: 1200px;
  margin: 24px auto;
  padding: 0 16px;
}
.filter-bar {
  margin-bottom: 16px;
  color: #909399;
  font-size: 14px;
}
.product-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 16px;
  min-height: 200px;
}
.product-card {
  cursor: pointer;
}
.product-img {
  height: 150px;
  background: #f5f7fa;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  margin-bottom: 12px;
}
.product-name {
  font-size: 15px;
  font-weight: 500;
  margin-bottom: 6px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.product-price {
  color: #f56c6c;
  font-size: 18px;
  font-weight: bold;
  margin-bottom: 4px;
}
.product-stock {
  color: #909399;
  font-size: 12px;
}
.pagination {
  margin-top: 24px;
  justify-content: center;
  display: flex;
}
</style>
