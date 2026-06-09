<template>
  <div class="home-page">
    <!-- Top bar: result count + sort + price range -->
    <div class="filter-bar">
      <span class="result-count">
        共 {{ total }} 件商品{{ route.query.keyword ? `（搜索：${route.query.keyword}）` : '' }}
        <span v-if="selectedCategory" class="active-filter"> · 分类：{{ selectedCategory }}</span>
      </span>
      <div class="filter-controls">
        <el-select v-model="sortOption" placeholder="默认排序" style="width:130px" @change="handleFilterChange">
          <el-option label="默认排序" value="" />
          <el-option label="价格升序" value="price_asc" />
          <el-option label="价格降序" value="price_desc" />
          <el-option label="销量降序" value="sales_desc" />
        </el-select>
        <el-input v-model="minPriceInput" placeholder="最低价" style="width:88px" clearable @change="handleFilterChange" />
        <span class="range-sep">~</span>
        <el-input v-model="maxPriceInput" placeholder="最高价" style="width:88px" clearable @change="handleFilterChange" />
      </div>
    </div>

    <!-- Main layout: optional category sidebar + product grid -->
    <div class="main-layout">
      <div v-if="categoryBuckets.length" class="category-sidebar">
        <div class="sidebar-title">商品分类</div>
        <div
          v-for="b in categoryBuckets"
          :key="b.category"
          :class="['category-item', { active: selectedCategory === b.category }]"
          @click="toggleCategory(b.category)"
        >
          <span>{{ b.category }}</span>
          <el-tag size="small" type="info" effect="plain">{{ b.count }}</el-tag>
        </div>
      </div>

      <div v-loading="loading" class="product-grid">
        <el-card
          v-for="p in list"
          :key="p.id"
          class="product-card"
          shadow="hover"
          :body-style="{ padding: '0' }"
          @click="$router.push(`/product/${p.id}`)"
        >
          <div class="product-img">
            <el-image v-if="p.imageUrl" :src="p.imageUrl" fit="cover" style="width:100%;height:100%" lazy />
            <el-icon v-else size="48" color="#c0c4cc"><Picture /></el-icon>
            <div class="stock-badge" v-if="stockLabel(p.stock)">
              <el-tag :type="stockLabel(p.stock).type" size="small" effect="dark">{{ stockLabel(p.stock).text }}</el-tag>
            </div>
          </div>
          <div class="product-info">
            <!-- highlightName contains only <em> tags from ES; safe for v-html -->
            <div class="product-name" v-html="p.highlightName || p.name"></div>
            <div class="product-price">¥{{ p.price }}</div>
          </div>
        </el-card>
        <el-empty v-if="!loading && list.length === 0" description="没有找到商品" style="grid-column:1/-1" />
      </div>
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
import { ElMessage } from 'element-plus'
import { Picture } from '@element-plus/icons-vue'
import { getProducts } from '@/api/product'

const route = useRoute()
const loading = ref(false)
const list = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(8)

const sortOption = ref('')
const minPriceInput = ref('')
const maxPriceInput = ref('')
const selectedCategory = ref('')
const categoryBuckets = ref([])

function stockLabel(stock) {
  if (stock === 0) return { text: '已售罄', type: 'danger' }
  if (stock <= 10) return { text: `仅剩 ${stock} 件`, type: 'warning' }
  return null
}

async function fetchList() {
  loading.value = true
  try {
    const params = {
      page: page.value,
      size: pageSize.value,
      keyword: route.query.keyword || ''
    }
    if (sortOption.value) params.sort = sortOption.value
    if (minPriceInput.value !== '') params.minPrice = minPriceInput.value
    if (maxPriceInput.value !== '') params.maxPrice = maxPriceInput.value
    if (selectedCategory.value) params.category = selectedCategory.value

    const data = await getProducts(params)
    list.value = data.products || []
    total.value = data.total || 0
    categoryBuckets.value = data.categoryBuckets || []
  } catch (err) {
    ElMessage.error(err.message || '商品加载失败，请刷新重试')
  } finally {
    loading.value = false
  }
}

function handleFilterChange() {
  page.value = 1
  fetchList()
}

function toggleCategory(cat) {
  selectedCategory.value = selectedCategory.value === cat ? '' : cat
  page.value = 1
  fetchList()
}

function handlePageChange(p) {
  page.value = p
  fetchList()
}

onMounted(fetchList)
watch(() => route.query.keyword, () => {
  page.value = 1
  selectedCategory.value = ''
  fetchList()
})
</script>

<style scoped>
.home-page {
  max-width: 1200px;
  margin: 24px auto;
  padding: 0 16px;
}
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
  color: #909399;
  font-size: 14px;
}
.result-count { flex-shrink: 0; }
.active-filter { color: #409eff; }
.filter-controls {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.range-sep { color: #c0c4cc; }

.main-layout {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}
.category-sidebar {
  min-width: 140px;
  flex-shrink: 0;
  background: #fff;
  border: 1px solid #ebeef5;
  border-radius: 4px;
  padding: 12px;
}
.sidebar-title {
  font-weight: 600;
  font-size: 14px;
  color: #303133;
  margin-bottom: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid #ebeef5;
}
.category-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 4px;
  cursor: pointer;
  border-radius: 4px;
  font-size: 13px;
  color: #606266;
  transition: background 0.2s;
}
.category-item:hover { background: #f5f7fa; }
.category-item.active { background: #ecf5ff; color: #409eff; font-weight: 500; }

.product-grid {
  flex: 1;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 16px;
  min-height: 200px;
}

/* 商品卡片 */
.product-card {
  cursor: pointer;
  border-radius: 8px;
  overflow: hidden;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.product-card:hover {
  transform: translateY(-3px);
}

.product-img {
  aspect-ratio: 3 / 2;
  background: #f5f7fa;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  position: relative;
}
.stock-badge {
  position: absolute;
  top: 8px;
  left: 8px;
}

.product-info {
  padding: 12px 14px 14px;
}
.product-name {
  font-size: 14px;
  font-weight: 500;
  color: #303133;
  margin-bottom: 8px;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  line-height: 1.45;
  min-height: 2.9em;
}
.product-price {
  color: #f56c6c;
  font-size: 18px;
  font-weight: 700;
}

.pagination { margin-top: 24px; justify-content: center; display: flex; }
:deep(.search-hl) { color: #f56c6c; font-style: normal; font-weight: 600; }
</style>
