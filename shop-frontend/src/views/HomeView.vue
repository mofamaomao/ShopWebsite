<template>
  <div class="home-page">
    <div class="filter-bar">共 {{ total }} 件商品{{ route.query.keyword ? `（搜索：${route.query.keyword}）` : '' }}</div>
    <div v-loading="loading" class="product-grid">
      <el-card
        v-for="p in list"
        :key="p.id"
        class="product-card"
        shadow="hover"
        @click="$router.push(`/product/${p.id}`)"
      >
        <div class="product-img">
          <el-image v-if="p.imageUrl" :src="p.imageUrl" fit="cover" style="width:100%;height:100%" />
          <el-icon v-else size="60" color="#c0c4cc"><Picture /></el-icon>
        </div>
        <!-- highlightName contains only <em> tags from ES; safe for v-html -->
        <div class="product-name" v-html="p.highlightName || p.name"></div>
        <div class="product-price">¥{{ p.price }}</div>
        <div class="product-stock">库存：{{ p.stock }}</div>
      </el-card>
      <el-empty v-if="!loading && list.length === 0" description="没有找到商品" style="grid-column:1/-1" />
    </div>
    <el-pagination
      v-if="total > pageSize"
      layout="prev, pager, next"
      :total="total"
      :page-size="pageSize"
      :current-page="page"
      @current-change="handlePageChange"
      class="pagination"
    />
  </div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Picture } from '@element-plus/icons-vue'
import { getProducts } from '@/api/product'

const route = useRoute()
const loading = ref(false)
const list = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(8)

async function fetchList() {
  loading.value = true
  try {
    const data = await getProducts({
      page: page.value,
      size: pageSize.value,
      keyword: route.query.keyword || ''
    })
    list.value = data.list || []
    total.value = data.total || 0
  } finally {
    loading.value = false
  }
}

function handlePageChange(p) {
  page.value = p
  fetchList()
}

onMounted(fetchList)
watch(() => route.query.keyword, () => { page.value = 1; fetchList() })
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
.product-card { cursor: pointer; }
.product-img {
  height: 150px;
  background: #f5f7fa;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  margin-bottom: 12px;
  overflow: hidden;
}
.product-name {
  font-size: 15px;
  font-weight: 500;
  margin-bottom: 6px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.product-price { color: #f56c6c; font-size: 18px; font-weight: bold; margin-bottom: 4px; }
.product-stock { color: #909399; font-size: 12px; }
.pagination { margin-top: 24px; justify-content: center; display: flex; }
:deep(.search-hl) { color: #f56c6c; font-style: normal; font-weight: 600; }
</style>
